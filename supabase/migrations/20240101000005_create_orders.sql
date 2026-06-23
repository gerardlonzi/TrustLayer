CREATE TYPE order_status AS ENUM (
  'pending',     
  'confirmed',    
  'processing',  
  'shipped',    
  'delivered',   
  'cancelled',   
  'refunded'     
);

CREATE TYPE payment_status AS ENUM (
  'pending',   
  'paid',      
  'failed',    
  'refunded'   
);

CREATE TABLE orders (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  buyer_id          UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  seller_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  affiliate_link_id UUID REFERENCES affiliate_links(id) ON DELETE SET NULL,

  total_amount      NUMERIC(12, 2) NOT NULL CHECK (total_amount > 0),
  platform_fee      NUMERIC(12, 2) NOT NULL DEFAULT 0,
  seller_amount     NUMERIC(12, 2) NOT NULL DEFAULT 0,

  status            order_status NOT NULL DEFAULT 'pending',
  payment_status    payment_status NOT NULL DEFAULT 'pending',

  -- External payment reference (CinetPay transaction ID)
  -- UNIQUE : one payment reference per order
  payment_ref       TEXT UNIQUE,
  payment_method    TEXT, -- 'mtn_momo' | 'orange_money' | 'card'

  shipping_name     TEXT,
  shipping_phone    TEXT,
  shipping_address  TEXT,
  shipping_city     TEXT,
  shipping_country  TEXT NOT NULL DEFAULT 'CM',

  requires_shipping BOOLEAN NOT NULL DEFAULT TRUE,

  notes             TEXT,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_update_orders_updated_at
  BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_orders_buyer
  ON orders(buyer_id, created_at DESC);

CREATE INDEX idx_orders_seller
  ON orders(seller_id, status);

CREATE INDEX idx_orders_affiliate
  ON orders(affiliate_link_id)
  WHERE affiliate_link_id IS NOT NULL;

CREATE INDEX idx_orders_status
  ON orders(status, payment_status);

CREATE TABLE order_items (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  order_id          UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id        UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,

  quantity          INT NOT NULL DEFAULT 1 CHECK (quantity > 0),

  unit_price        NUMERIC(12, 2) NOT NULL,
  commission_rate   NUMERIC(5, 2)  NOT NULL,

  commission_amount NUMERIC(12, 2) NOT NULL DEFAULT 0,

  digital_file_url  TEXT,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_order_items_order
  ON order_items(order_id);

CREATE INDEX idx_order_items_product
  ON order_items(product_id);

CREATE OR REPLACE FUNCTION update_product_stats()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN
    UPDATE products p
    SET
      total_sales   = total_sales + oi.quantity,
      total_revenue = total_revenue + (oi.unit_price * oi.quantity)
    FROM order_items oi
    WHERE oi.order_id = NEW.id
      AND p.id = oi.product_id;
  END IF;

  IF NEW.status = 'cancelled' AND OLD.status = 'confirmed' THEN
    UPDATE products p
    SET
      total_sales   = GREATEST(0, total_sales - oi.quantity),
      total_revenue = GREATEST(0, total_revenue - (oi.unit_price * oi.quantity))
    FROM order_items oi
    WHERE oi.order_id = NEW.id
      AND p.id = oi.product_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_product_stats
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION update_product_stats();

CREATE OR REPLACE FUNCTION mark_click_converted()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'confirmed'
     AND OLD.status != 'confirmed'
     AND NEW.affiliate_link_id IS NOT NULL
  THEN
    UPDATE click_events
    SET converted = TRUE
    WHERE id = (
      SELECT id FROM click_events
      WHERE affiliate_link_id = NEW.affiliate_link_id
        AND converted = FALSE
      ORDER BY created_at DESC
      LIMIT 1
    );

    UPDATE affiliate_links
    SET conversions = conversions + 1
    WHERE id = NEW.affiliate_link_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_mark_click_converted
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION mark_click_converted();

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "orders — buyer reads own"
  ON orders FOR SELECT
  USING (auth.uid() = buyer_id);

CREATE POLICY "orders — seller reads own"
  ON orders FOR SELECT
  USING (
    auth.uid() = seller_id
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'seller'
    )
  );

CREATE POLICY "orders — buyer creates"
  ON orders FOR INSERT
  WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "orders — seller updates status"
  ON orders FOR UPDATE
  USING (
    auth.uid() = seller_id
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'seller'
    )
  )
  WITH CHECK (
    status IN ('processing', 'shipped', 'delivered')
    AND total_amount = (SELECT total_amount FROM orders WHERE id = orders.id)
    AND payment_status = (SELECT payment_status FROM orders WHERE id = orders.id)
  );

CREATE POLICY "orders — admin full access"
  ON orders FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "order_items — buyer reads own"
  ON order_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM orders
      WHERE id = order_items.order_id
        AND buyer_id = auth.uid()
    )
  );

CREATE POLICY "order_items — seller reads own"
  ON order_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM orders
      WHERE id = order_items.order_id
        AND seller_id = auth.uid()
    )
  );

CREATE POLICY "order_items — buyer inserts"
  ON order_items FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders
      WHERE id = order_items.order_id
        AND buyer_id = auth.uid()
    )
  );

CREATE POLICY "order_items — admin full access"
  ON order_items FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );