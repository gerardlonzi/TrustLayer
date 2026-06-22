
CREATE TABLE affiliate_links (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  creator_id  UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  code        TEXT NOT NULL UNIQUE
              CHECK (length(code) >= 4 AND length(code) <= 20),
  clicks      INT NOT NULL DEFAULT 0,
  conversions INT NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_affiliate_link_creator_product
    UNIQUE (creator_id, product_id)
);

CREATE INDEX idx_affiliate_links_creator ON affiliate_links(creator_id);
CREATE INDEX idx_affiliate_links_product ON affiliate_links(product_id);
CREATE INDEX idx_affiliate_links_code    ON affiliate_links(code);

CREATE TABLE click_events (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  affiliate_link_id UUID NOT NULL
                    REFERENCES affiliate_links(id) ON DELETE CASCADE,

  ip_hash           TEXT NOT NULL,

  browser_fingerprint TEXT,

  visitor_token     TEXT,

  buyer_id          UUID REFERENCES profiles(id) ON DELETE SET NULL,

  user_agent        TEXT,
  referrer          TEXT,
  converted         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_click_events_link_ip
  ON click_events(affiliate_link_id, ip_hash);

CREATE INDEX idx_click_events_fingerprint
  ON click_events(affiliate_link_id, browser_fingerprint)
  WHERE browser_fingerprint IS NOT NULL;

CREATE INDEX idx_click_events_visitor
  ON click_events(affiliate_link_id, visitor_token)
  WHERE visitor_token IS NOT NULL;

CREATE INDEX idx_click_events_created
  ON click_events(created_at DESC);

CREATE OR REPLACE FUNCTION increment_link_clicks()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE affiliate_links
  SET clicks = clicks + 1
  WHERE id = NEW.affiliate_link_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_increment_clicks
  AFTER INSERT ON click_events
  FOR EACH ROW EXECUTE FUNCTION increment_link_clicks();

CREATE OR REPLACE FUNCTION is_suspicious_click(
  p_affiliate_link_id UUID,
  p_ip_hash           TEXT,
  p_fingerprint       TEXT,
  p_visitor_token     TEXT,
  p_buyer_id          UUID,
  p_window_minutes    INT DEFAULT 60
)
RETURNS BOOLEAN AS $$
DECLARE
  v_creator_id  UUID;
  v_click_count INT;
BEGIN
  SELECT creator_id INTO v_creator_id
  FROM affiliate_links WHERE id = p_affiliate_link_id;

  IF v_creator_id = p_buyer_id AND p_buyer_id IS NOT NULL THEN
    RETURN TRUE;
  END IF;

  SELECT COUNT(*) INTO v_click_count
  FROM click_events
  WHERE affiliate_link_id = p_affiliate_link_id
    AND ip_hash = p_ip_hash
    AND created_at >= NOW() - (p_window_minutes || ' minutes')::INTERVAL;

  IF v_click_count >= 3 THEN
    RETURN TRUE; 
  END IF;

  IF p_fingerprint IS NOT NULL THEN
    SELECT COUNT(*) INTO v_click_count
    FROM click_events
    WHERE affiliate_link_id = p_affiliate_link_id
      AND browser_fingerprint = p_fingerprint
      AND created_at >= NOW() - (p_window_minutes || ' minutes')::INTERVAL;

    IF v_click_count >= 3 THEN
      RETURN TRUE; 
    END IF;
  END IF;

  IF p_visitor_token IS NOT NULL THEN
    SELECT COUNT(*) INTO v_click_count
    FROM click_events
    WHERE affiliate_link_id = p_affiliate_link_id
      AND visitor_token = p_visitor_token
      AND created_at >= NOW() - (p_window_minutes || ' minutes')::INTERVAL;

    IF v_click_count >= 3 THEN
      RETURN TRUE; 
    END IF;
  END IF;

  RETURN FALSE; 
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

ALTER TABLE affiliate_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY "affiliate_links — public read active"
  ON affiliate_links FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "affiliate_links — creator manages own"
  ON affiliate_links FOR ALL
  USING (
    auth.uid() = creator_id
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'creator'
    )
  )
  WITH CHECK (
    auth.uid() = creator_id
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'creator'
    )
  );

CREATE POLICY "affiliate_links — admin full access"
  ON affiliate_links FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

ALTER TABLE click_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "click_events — public insert"
  ON click_events FOR INSERT
  WITH CHECK (TRUE);

CREATE POLICY "click_events — creator reads own"
  ON click_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM affiliate_links al
      WHERE al.id = click_events.affiliate_link_id
        AND al.creator_id = auth.uid()
    )
  );

CREATE POLICY "click_events — admin full access"
  ON click_events FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );