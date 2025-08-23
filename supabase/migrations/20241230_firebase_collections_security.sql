-- Firebase koleksiyonları ve güvenlik kuralları için SQL migration
-- Bu dosya Firebase Firestore yapısını PostgreSQL'e uyarlamak için kullanılır

-- Otomatik rota güncellemeleri tablosu
CREATE TABLE IF NOT EXISTS automatic_route_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id TEXT NOT NULL,
    user_id TEXT,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    region_id TEXT,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Şoför bildirimleri tablosu
CREATE TABLE IF NOT EXISTS driver_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id TEXT NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT NOT NULL,
    priority TEXT DEFAULT 'medium',
    source TEXT DEFAULT 'system',
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    read_at TIMESTAMP WITH TIME ZONE
);

-- Rota yenileme tetikleyicileri tablosu
CREATE TABLE IF NOT EXISTS route_refresh_triggers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id TEXT NOT NULL,
    triggered_by TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    processed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Yakınlık verileri tablosu
CREATE TABLE IF NOT EXISTS proximity_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    driver_id TEXT NOT NULL,
    distance DOUBLE PRECISION NOT NULL,
    user_location POINT NOT NULL,
    driver_location POINT NOT NULL,
    date DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Yakınlık olayları tablosu
CREATE TABLE IF NOT EXISTS proximity_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    driver_id TEXT NOT NULL,
    distance DOUBLE PRECISION NOT NULL,
    event_type TEXT NOT NULL,
    date DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ETA hesaplama verileri tablosu
CREATE TABLE IF NOT EXISTS eta_calculations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id TEXT NOT NULL,
    passenger_id TEXT NOT NULL,
    region_id TEXT NOT NULL,
    estimated_arrival_time TIMESTAMP WITH TIME ZONE NOT NULL,
    current_stop_name TEXT,
    current_stop_order INTEGER,
    total_stops INTEGER,
    driver_distance DOUBLE PRECISION,
    average_speed DOUBLE PRECISION,
    traffic_factor DOUBLE PRECISION DEFAULT 1.0,
    is_real_time BOOLEAN DEFAULT TRUE,
    calculation_method TEXT DEFAULT 'enhanced',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Rota geçmişi oturumları tablosu
CREATE TABLE IF NOT EXISTS route_history_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    start_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    end_time TIMESTAMP WITH TIME ZONE,
    total_distance DOUBLE PRECISION DEFAULT 0,
    completed_stops INTEGER DEFAULT 0,
    total_stops INTEGER DEFAULT 0,
    region_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Rota geçmişi kayıtları tablosu
CREATE TABLE IF NOT EXISTS route_history_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES route_history_sessions(id) ON DELETE CASCADE,
    driver_id TEXT NOT NULL,
    stop_id TEXT NOT NULL,
    stop_name TEXT NOT NULL,
    stop_location POINT NOT NULL,
    arrival_time TIMESTAMP WITH TIME ZONE,
    departure_time TIMESTAMP WITH TIME ZONE,
    passenger_count INTEGER DEFAULT 0,
    stop_order INTEGER NOT NULL,
    distance_from_previous DOUBLE PRECISION,
    duration_at_stop INTEGER, -- saniye cinsinden
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Sesli navigasyon kayıtları tablosu
CREATE TABLE IF NOT EXISTS voice_navigation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id TEXT NOT NULL,
    instruction_type TEXT NOT NULL,
    instruction_text TEXT NOT NULL,
    language TEXT DEFAULT 'tr',
    is_played BOOLEAN DEFAULT FALSE,
    played_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Simülasyon kayıtları tablosu
CREATE TABLE IF NOT EXISTS simulation_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id TEXT NOT NULL,
    simulation_type TEXT NOT NULL,
    start_location POINT NOT NULL,
    end_location POINT NOT NULL,
    current_location POINT NOT NULL,
    speed DOUBLE PRECISION DEFAULT 30.0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- İndeksler oluştur
CREATE INDEX IF NOT EXISTS idx_automatic_route_updates_driver_id ON automatic_route_updates(driver_id);
CREATE INDEX IF NOT EXISTS idx_automatic_route_updates_created_at ON automatic_route_updates(created_at);

CREATE INDEX IF NOT EXISTS idx_driver_notifications_driver_id ON driver_notifications(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_notifications_is_read ON driver_notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_driver_notifications_created_at ON driver_notifications(created_at);

CREATE INDEX IF NOT EXISTS idx_route_refresh_triggers_driver_id ON route_refresh_triggers(driver_id);
CREATE INDEX IF NOT EXISTS idx_route_refresh_triggers_status ON route_refresh_triggers(status);

CREATE INDEX IF NOT EXISTS idx_proximity_data_user_id ON proximity_data(user_id);
CREATE INDEX IF NOT EXISTS idx_proximity_data_driver_id ON proximity_data(driver_id);
CREATE INDEX IF NOT EXISTS idx_proximity_data_date ON proximity_data(date);

CREATE INDEX IF NOT EXISTS idx_proximity_events_user_id ON proximity_events(user_id);
CREATE INDEX IF NOT EXISTS idx_proximity_events_date ON proximity_events(date);

CREATE INDEX IF NOT EXISTS idx_eta_calculations_driver_id ON eta_calculations(driver_id);
CREATE INDEX IF NOT EXISTS idx_eta_calculations_passenger_id ON eta_calculations(passenger_id);
CREATE INDEX IF NOT EXISTS idx_eta_calculations_created_at ON eta_calculations(created_at);

CREATE INDEX IF NOT EXISTS idx_route_history_sessions_driver_id ON route_history_sessions(driver_id);
CREATE INDEX IF NOT EXISTS idx_route_history_sessions_status ON route_history_sessions(status);

CREATE INDEX IF NOT EXISTS idx_route_history_records_session_id ON route_history_records(session_id);
CREATE INDEX IF NOT EXISTS idx_route_history_records_driver_id ON route_history_records(driver_id);
CREATE INDEX IF NOT EXISTS idx_route_history_records_stop_order ON route_history_records(stop_order);

CREATE INDEX IF NOT EXISTS idx_voice_navigation_logs_driver_id ON voice_navigation_logs(driver_id);
CREATE INDEX IF NOT EXISTS idx_voice_navigation_logs_created_at ON voice_navigation_logs(created_at);

CREATE INDEX IF NOT EXISTS idx_simulation_records_driver_id ON simulation_records(driver_id);
CREATE INDEX IF NOT EXISTS idx_simulation_records_is_active ON simulation_records(is_active);

-- Trigger fonksiyonları
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Updated_at trigger'ları
CREATE TRIGGER update_automatic_route_updates_updated_at
    BEFORE UPDATE ON automatic_route_updates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_eta_calculations_updated_at
    BEFORE UPDATE ON eta_calculations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_route_history_sessions_updated_at
    BEFORE UPDATE ON route_history_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_simulation_records_updated_at
    BEFORE UPDATE ON simulation_records
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- RLS (Row Level Security) politikaları
ALTER TABLE automatic_route_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE route_refresh_triggers ENABLE ROW LEVEL SECURITY;
ALTER TABLE proximity_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE proximity_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE eta_calculations ENABLE ROW LEVEL SECURITY;
ALTER TABLE route_history_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE route_history_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_navigation_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE simulation_records ENABLE ROW LEVEL SECURITY;

-- Güvenlik politikaları
-- Otomatik rota güncellemeleri
CREATE POLICY "Users can view their own route updates" ON automatic_route_updates
    FOR SELECT USING (auth.uid()::text = driver_id OR auth.uid()::text = user_id);

CREATE POLICY "System can insert route updates" ON automatic_route_updates
    FOR INSERT WITH CHECK (true);

-- Şoför bildirimleri
CREATE POLICY "Drivers can view their notifications" ON driver_notifications
    FOR SELECT USING (auth.uid()::text = driver_id);

CREATE POLICY "Drivers can update their notifications" ON driver_notifications
    FOR UPDATE USING (auth.uid()::text = driver_id);

CREATE POLICY "System can insert notifications" ON driver_notifications
    FOR INSERT WITH CHECK (true);

-- Rota yenileme tetikleyicileri
CREATE POLICY "Drivers can view their triggers" ON route_refresh_triggers
    FOR SELECT USING (auth.uid()::text = driver_id);

CREATE POLICY "System can manage triggers" ON route_refresh_triggers
    FOR ALL WITH CHECK (true);

-- Yakınlık verileri
CREATE POLICY "Users can view their proximity data" ON proximity_data
    FOR SELECT USING (auth.uid()::text = user_id OR auth.uid()::text = driver_id);

CREATE POLICY "System can insert proximity data" ON proximity_data
    FOR INSERT WITH CHECK (true);

-- Yakınlık olayları
CREATE POLICY "Users can view their proximity events" ON proximity_events
    FOR SELECT USING (auth.uid()::text = user_id OR auth.uid()::text = driver_id);

CREATE POLICY "System can insert proximity events" ON proximity_events
    FOR INSERT WITH CHECK (true);

-- ETA hesaplamaları
CREATE POLICY "Users can view their ETA calculations" ON eta_calculations
    FOR SELECT USING (auth.uid()::text = driver_id OR auth.uid()::text = passenger_id);

CREATE POLICY "System can manage ETA calculations" ON eta_calculations
    FOR ALL WITH CHECK (true);

-- Rota geçmişi oturumları
CREATE POLICY "Drivers can view their route sessions" ON route_history_sessions
    FOR SELECT USING (auth.uid()::text = driver_id);

CREATE POLICY "System can manage route sessions" ON route_history_sessions
    FOR ALL WITH CHECK (true);

-- Rota geçmişi kayıtları
CREATE POLICY "Drivers can view their route records" ON route_history_records
    FOR SELECT USING (auth.uid()::text = driver_id);

CREATE POLICY "System can manage route records" ON route_history_records
    FOR ALL WITH CHECK (true);

-- Sesli navigasyon kayıtları
CREATE POLICY "Drivers can view their voice logs" ON voice_navigation_logs
    FOR SELECT USING (auth.uid()::text = driver_id);

CREATE POLICY "System can manage voice logs" ON voice_navigation_logs
    FOR ALL WITH CHECK (true);

-- Simülasyon kayıtları
CREATE POLICY "Drivers can view their simulation records" ON simulation_records
    FOR SELECT USING (auth.uid()::text = driver_id);

CREATE POLICY "System can manage simulation records" ON simulation_records
    FOR ALL WITH CHECK (true);

-- Yorum: Bu migration Firebase Firestore koleksiyonlarını PostgreSQL tablolarına dönüştürür
-- ve uygun güvenlik kurallarını (RLS) uygular.