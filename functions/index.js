const functions = require("firebase-functions");
const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

exports.cleanupExpiredMessages = require("firebase-functions/v2/scheduler").onSchedule("every 15 minutes", async (event) => {
  try {
    const now = admin.firestore.Timestamp.now();
    const snap = await admin.firestore().collection('messages')
      .where('expireAfterHours', '>', 0)
      .limit(500)
      .get();

    if (snap.empty) return null;

    const expiredMessages = [];
    const currentTime = new Date();

    for (const doc of snap.docs) {
      const data = doc.data();
      const timestamp = data.timestamp;
      const expireAfterHours = data.expireAfterHours;

      if (timestamp && expireAfterHours && expireAfterHours > 0) {
        const messageTime = timestamp.toDate();
        const expiryTime = new Date(messageTime.getTime() + (expireAfterHours * 60 * 60 * 1000));

        if (currentTime > expiryTime) {
          expiredMessages.push(doc);
        }
      }
    }

    if (expiredMessages.length === 0) return null;

    const batch = admin.firestore().batch();
    for (const doc of expiredMessages) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    console.log(`cleanupExpiredMessages: deleted ${expiredMessages.length} expired messages`);
    return null;
  } catch (e) {
    console.error('cleanupExpiredMessages error', e);
    return null;
  }
});

exports.addDriverHttp = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).send("Sadece POST desteklenir.");
  }

  const { name, email, password, region, vehiclePlate } = req.body;

  if (!name || !email || !password || !region || !vehiclePlate) {
    return res.status(400).send("Tüm alanlar doldurulmalı.");
  }

  try {
    const userRecord = await admin.auth().createUser({
      email,
      password,
      displayName: name,
    });

    await admin.firestore().collection("drivers").doc(userRecord.uid).set({
      name,
      email,
      regionId: region,
      vehiclePlate,
      status: "active",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return res.send({ uid: userRecord.uid });
  } catch (error) {
    console.error(error);
    res.status(500).send(error.message);
  }
});

exports.createRoute = onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(200).send('');
    return;
  }

  if (req.method !== "POST") {
    return res.status(405).send("Sadece POST desteklenir.");
  }

  const { origin, waypoints, optimize } = req.body;

  if (!origin || !waypoints || waypoints.length === 0) {
    return res.status(400).send("Origin ve waypoints gerekli.");
  }

  try {
    const cfg = functions.config();
    const apiKey = cfg.google && cfg.google.maps_api_key;
    if (!apiKey) {
      return res.status(500).send("Google Maps API key bulunamadı.");
    }

    const waypointsStr = waypoints.map(wp => `${wp.lat},${wp.lng}`).join('|');
    const optimizeParam = optimize ? 'true' : 'false';

    const directionsUrl = `https://maps.googleapis.com/maps/api/directions/json?origin=${origin.lat},${origin.lng}&destination=${origin.lat},${origin.lng}&waypoints=optimize:${optimizeParam}|${waypointsStr}&key=${apiKey}`;

    const response = await axios.get(directionsUrl);

    if (response.data.status !== 'OK') {
      return res.status(400).send(`Directions API hatası: ${response.data.status}`);
    }

    const route = response.data.routes[0];
    const leg = route.legs[0];

    const overviewPolyline = route.overview_polyline.points;

    const waypointOrder = route.waypoint_order || [];

    const routeData = {
      overview_polyline: {
        points: overviewPolyline
      },
      waypoint_order: waypointOrder,
      legs: route.legs,
      duration: leg.duration,
      distance: leg.distance,
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    };

    const routeRef = await admin.firestore().collection('routes').add(routeData);

    return res.send({
      routeId: routeRef.id,
      overview_polyline: overviewPolyline,
      waypoint_order: waypointOrder,
      duration: leg.duration,
      distance: leg.distance
    });
  } catch (error) {
    console.error('Rota oluşturma hatası:', error);
    res.status(500).send(error.message);
  }
});

function haversineDistance(lat1, lon1, lat2, lon2) {
  function toRad(x) { return x * Math.PI / 180; }
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

exports.onLiveLocationUpdate = onDocumentWritten('live_locations/{driverId}', async (event) => {
  try {
    const after = event.data.after ? event.data.after.data() : null;
    if (!after) return null;

    const driverId = event.params.driverId;
    const driverLat = parseFloat(after.lat);
    const driverLng = parseFloat(after.lng);
    if (isNaN(driverLat) || isNaN(driverLng)) return null;

    const driverDoc = await admin.firestore().collection('drivers').doc(driverId).get();
    if (!driverDoc.exists) return null;
    const regionId = driverDoc.data().regionId;
    if (!regionId) return null;

    const alertsSnap = await admin.firestore()
      .collection('distance_alerts')
      .where('regionId', '==', regionId)
      .where('isActive', '==', true)
      .get();

    const messaging = admin.messaging();
    const batch = admin.firestore().batch();

    for (const alertDoc of alertsSnap.docs) {
      const alert = alertDoc.data();
      const passengerId = alert.passengerId;
      const alertDistance = Number(alert.alertDistanceMeters || 0);
      const passengerLat = Number(alert.passengerLat);
      const passengerLng = Number(alert.passengerLng);
      const repeat = alert.repeat !== false;
      const isInside = !!alert.isInside;
      if (!passengerId || !alertDistance || isNaN(passengerLat) || isNaN(passengerLng)) continue;

      const distance = haversineDistance(driverLat, driverLng, passengerLat, passengerLng);
      if (distance <= alertDistance && !isInside) {
        const userDoc = await admin.firestore().collection('users').doc(passengerId).get();
        const fcmToken = userDoc.exists ? userDoc.data().fcmToken : null;

        const payload = {
          token: fcmToken,
          notification: {
            title: '🚌 Servis Yaklaştı!',
            body: `Servis ${Math.max(distance / 1000, 0.1).toFixed(1)} km mesafenizde. Hazır olun!`,
          },
          data: {
            type: 'distance_alert',
            distance: String(distance),
            alertDistance: String(alertDistance),
          },
        };

        if (fcmToken) {
          try { await messaging.send(payload); } catch (e) { console.error('FCM send error', e.message); }
        }

        batch.update(alertDoc.ref, {
          isInside: true,
          triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
          actualDistance: distance,
          ...(repeat ? {} : { isActive: false }),
        });
      } else if (distance > (alertDistance + 30) && isInside) {
        batch.update(alertDoc.ref, {
          isInside: false,
          lastChecked: admin.firestore.FieldValue.serverTimestamp(),
          ...(repeat ? { isActive: true } : {}),
        });
      }
    }

    await batch.commit();
    return null;
  } catch (e) {
    console.error('onLiveLocationUpdate error', e);
    return null;
  }
});

exports.onPermissionWrite = onDocumentWritten('permissions/{permissionId}', async (event) => {
  try {
    const after = event.data.after ? event.data.after.data() : null;
    const before = event.data.before ? event.data.before.data() : null;

    let userId, isActive;
    if (after) { userId = after.userId; isActive = !!after.isActive; }
    else if (before) { userId = before.userId; isActive = false; }
    else { return null; }

    if (!userId) return null;

    const stopsSnap = await admin.firestore()
      .collection('enhanced_stops')
      .where('passengerIds', 'array-contains', userId)
      .where('isActive', '==', true)
      .get();

    const batch = admin.firestore().batch();
    for (const doc of stopsSnap.docs) {
      batch.update(doc.ref, {
        temporarilyInactive: isActive,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    try {
      const driverId = (after && after.driverId) || (before && before.driverId);
      if (driverId) {
        await admin.firestore().collection('route_refresh_triggers').add({
          driverId,
          triggeredBy: 'permission_update',
          status: 'pending',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      console.error('route_refresh_triggers write error', e);
    }
    return null;
  } catch (e) {
    console.error('onPermissionWrite error', e);
    return null;
  }
});

exports.simulateDistanceAlert = onRequest(async (req, res) => {
  try {
    if (req.method !== 'POST') return res.status(405).send('POST gerekli');
    const { passengerId, message } = req.body;
    if (!passengerId) return res.status(400).send('passengerId gerekli');

    const userDoc = await admin.firestore().collection('users').doc(passengerId).get();
    if (!userDoc.exists) return res.status(404).send('Kullanıcı bulunamadı');
    const fcmToken = userDoc.data().fcmToken;
    if (!fcmToken) return res.status(400).send('Kullanıcının fcmToken kaydı yok');

    await admin.messaging().send({
      token: fcmToken,
      notification: {
        title: '🧪 Test Mesafe Bildirimi',
        body: message || 'Test: Servis yaklaştı simülasyonu',
      },
      data: { type: 'distance_alert_test' },
    });

    return res.send({ ok: true });
  } catch (e) {
    console.error(e);
    return res.status(500).send(e.message);
  }
});

exports.onStopLogCreate = onDocumentCreated('stop_logs/{logId}', async (event) => {
  try {
    const data = event.data.data();
    if (!data) return null;
    if (data.status && data.status !== 'arrived') return null;

    const passengerIds = Array.isArray(data.passengerIds) ? data.passengerIds : [];
    const stopAddress = data.stopAddress || 'Durak';
    if (passengerIds.length === 0) return null;

    const messaging = admin.messaging();

    for (const passengerId of passengerIds) {
      try {
        const userDoc = await admin.firestore().collection('users').doc(passengerId).get();
        const token = userDoc.exists ? userDoc.data().fcmToken : null;
        if (!token) continue;

        await messaging.send({
          token,
          notification: {
            title: '🚌 Servis Durağa Ulaştı',
            body: `${stopAddress} konumundayız. Lütfen hazır olun.`,
          },
          data: {
            type: 'stop_arrival',
            stopId: data.stopId || '',
            driverId: data.driverId || '',
          },
        });
      } catch (e) {
        console.error('FCM send stop_arrival error', e.message);
      }
    }
    return null;
  } catch (e) {
    console.error('onStopLogCreate error', e);
    return null;
  }
});

exports.onMessageCreate = onDocumentCreated('messages/{messageId}', async (event) => {
  try {
    const data = event.data.data();
    if (!data) return null;

    const expireAfterHours = Number(data.expireAfterHours || 0);
    if (expireAfterHours > 0) {
      try {
        const messageRef = event.data.ref;
        const expiresAt = admin.firestore.Timestamp.fromDate(
          new Date(Date.now() + expireAfterHours * 60 * 60 * 1000)
        );
        await messageRef.set({ expiresAt }, { merge: true });
      } catch (e) {
        console.error('expireAt set error', e);
      }
    }

    const regionId = data.regionId;
    const senderId = data.senderId;
    const senderName = data.senderName || 'Kullanıcı';
    const content = data.content || '';
    const isUrgent = !!data.isUrgent;
    const type = data.type || 'chat';
    const senderRole = data.senderRole || '';

    console.log(`onMessageCreate başladı: ${senderName} (${senderRole}) -> ${content}`);
    console.log(`- RegionId: ${regionId}`);
    console.log(`- SenderId: ${senderId}`);
    console.log(`- Type: ${type}`);
    console.log(`- IsUrgent: ${isUrgent}`);

    let recipientUserIds = new Set();

    if (regionId) {
      console.log(`🔍 Bölge ID: ${regionId} için alıcılar aranıyor...`);

      try {
        const usersSnap = await admin.firestore()
          .collection('users')
          .where('regionId', '==', regionId)
          .get();

        console.log(`📋 Users koleksiyonunda ${usersSnap.docs.length} doküman bulundu`);
        usersSnap.docs.forEach(doc => {
          const data = doc.data();
          console.log(`  - User: ${doc.id} (${data.name || 'İsimsiz'}) - Role: ${data.role || 'Rol yok'}`);
          if (doc.id !== senderId) {
            recipientUserIds.add(doc.id);
          }
        });
        console.log(`✅ Users'dan eklenen alıcılar: ${Array.from(recipientUserIds).join(', ')}`);
      } catch (e) {
        console.error('❌ Users koleksiyonu sorgulama hatası:', e);
      }

      try {
        const driversSnap = await admin.firestore()
          .collection('drivers')
          .where('regionId', '==', regionId)
          .get();

        console.log(`🚌 Drivers koleksiyonunda ${driversSnap.docs.length} doküman bulundu`);
        driversSnap.docs.forEach(doc => {
          const data = doc.data();
          console.log(`  - Driver: ${doc.id} (${data.name || 'İsimsiz'}) - FCM: ${data.fcmToken ? '✅' : '❌'}`);
          if (doc.id !== senderId) {
            recipientUserIds.add(doc.id);
          }
        });
        console.log(`✅ Drivers'dan eklenen alıcılar: ${driversSnap.docs.map(d => d.id).join(', ')}`);
      } catch (e) {
        console.error('❌ Drivers koleksiyonu sorgulama hatası:', e);
      }

      console.log(`📊 Toplam benzersiz alıcı sayısı: ${recipientUserIds.size}`);
      console.log(`🎯 Final alıcı listesi: ${Array.from(recipientUserIds).join(', ')}`);
    } else {
      console.log('❌ RegionId bulunamadı, alıcı aranamaz!');
    }

    if (recipientUserIds.size === 0) {
      console.log('Alıcı bulunamadı, bildirim gönderilmeyecek');
      return null;
    }

    console.log(`Toplam ${recipientUserIds.size} alıcıya bildirim gönderilecek`);

    const messaging = admin.messaging();
    const sentNotifications = new Set();

    for (const uid of recipientUserIds) {
      try {
        const notificationKey = `${uid}_${event.data.id}`;
        if (sentNotifications.has(notificationKey)) continue;

        console.log(`🔍 Kullanıcı ${uid} için FCM token aranıyor...`);

        let userDoc = await admin.firestore().collection('users').doc(uid).get();
        let userData = userDoc.exists ? userDoc.data() : null;
        let dataSource = 'users';

        if (userDoc.exists) {
          console.log(`  ✅ Users koleksiyonunda bulundu: ${uid}`);
          console.log(`  - Name: ${userData?.name || 'İsimsiz'}`);
          console.log(`  - Role: ${userData?.role || 'Rol yok'}`);
          console.log(`  - FCM Token: ${userData?.fcmToken ? '✅' : '❌'}`);
        }

        if (!userData) {
          console.log(`  🔍 Users'da bulunamadı, drivers'da aranıyor: ${uid}`);
          const driverDoc = await admin.firestore().collection('drivers').doc(uid).get();
          if (driverDoc.exists) {
            userData = driverDoc.data();
            dataSource = 'drivers';
            console.log(`  ✅ Şoför bilgisi drivers koleksiyonundan alındı: ${uid}`);
            console.log(`  - Name: ${userData?.name || 'İsimsiz'}`);
            console.log(`  - FCM Token: ${userData?.fcmToken ? '✅' : '❌'}`);
          } else {
            console.log(`  ❌ Kullanıcı hem users hem drivers koleksiyonunda bulunamadı: ${uid}`);
          }
        }

        if (!userData) {
          console.log(`❌ Kullanıcı bilgisi bulunamadı: ${uid}`);
          continue;
        }

        const fcmToken = userData.fcmToken;
        if (!fcmToken) {
          console.log(`❌ FCM token bulunamadı: ${uid} - Koleksiyon: ${dataSource}`);
          console.log(`📋 Kullanıcı verisi:`, JSON.stringify(userData, null, 2));
          continue;
        }

        console.log(`✅ FCM token bulundu: ${uid} - Koleksiyon: ${dataSource}`);
        console.log(`  - Token: ${fcmToken.substring(0, 20)}...`);

        let title, body;

        if (senderRole === 'Yolcu') {
          title = isUrgent ? '🚨 Acil Yolcu Mesajı' : '👤 Yolcu Mesajı';
          body = `${senderName}: ${content}`.substring(0, 180);
        } else if (senderRole === 'Şoför') {
          title = isUrgent ? '🚨 Acil Şoför Mesajı' : '🚌 Şoför Mesajı';
          body = `${senderName}: ${content}`.substring(0, 180);
        } else {
          title = isUrgent ? '🚨 Acil Mesaj' : '💬 Yeni Mesaj';
          body = `${senderName}: ${content}`.substring(0, 180);
        }

        console.log(`🚀 FCM bildirimi gönderiliyor: ${uid}`);
        console.log(`  - Title: ${title}`);
        console.log(`  - Body: ${body}`);
        console.log(`  - Token: ${fcmToken.substring(0, 20)}...`);

        const message = {
          token: fcmToken,
          notification: {
            title,
            body,
          },
          data: {
            type: 'chat_message',
            messageId: event.data.id,
            regionId: regionId || '',
            senderId: senderId || '',
            senderName: senderName || '',
            senderRole: senderRole || '',
            isUrgent: String(isUrgent),
            timestamp: String(Date.now()),
          },
        };

        console.log(`📤 FCM message objesi:`, JSON.stringify(message, null, 2));

        const response = await messaging.send(message);
        console.log(`✅ FCM response:`, response);

        sentNotifications.add(notificationKey);
        console.log(`✅ Bildirim gönderildi: ${uid} -> ${title}: ${body}`);
        console.log(`- FCM Token: ${fcmToken.substring(0, 20)}...`);
        console.log(`- Koleksiyon: ${dataSource}`);

      } catch (e) {
        console.error(`❌ FCM send chat error for user ${uid}:`, e.message);
      }
    }

    console.log(`🎯 onMessageCreate tamamlandı: ${sentNotifications.size} kullanıcıya bildirim gönderildi`);
    console.log(`📊 Özet:`);
    console.log(`- Toplam alıcı: ${recipientUserIds.size}`);
    console.log(`- Başarılı bildirim: ${sentNotifications.size}`);
    console.log(`- Başarısız: ${recipientUserIds.size - sentNotifications.size}`);
    return null;
  } catch (e) {
    console.error('❌ onMessageCreate error', e);
    return null;
  }
});
