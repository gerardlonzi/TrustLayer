CREATE TABLE reviews (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  buyer_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  order_id    UUID NOT NULL REFERENCES orders(id)   ON DELETE CASCADE,
  rating      INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT CHECK (length(comment) <= 2000),
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_review_buyer_product UNIQUE (buyer_id, product_id)
);

CREATE TRIGGER trg_update_reviews_updated_at
  BEFORE UPDATE ON reviews
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_reviews_product
  ON reviews(product_id, rating DESC);

CREATE INDEX idx_reviews_buyer
  ON reviews(buyer_id);

CREATE OR REPLACE FUNCTION validate_review_purchase()
RETURNS TRIGGER AS $$
DECLARE
  v_order_status order_status;
BEGIN
  SELECT o.status INTO v_order_status
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.id
  WHERE o.id          = NEW.order_id
    AND oi.product_id = NEW.product_id
    AND o.buyer_id    = NEW.buyer_id;

  IF v_order_status IS NULL THEN
    RAISE EXCEPTION 'REVIEW_NOT_PURCHASED: You must purchase this product before leaving a review';
  END IF;

  IF v_order_status != 'delivered' THEN
    RAISE EXCEPTION 'REVIEW_NOT_DELIVERED: Order must be delivered before leaving a review';
  END IF;

  NEW.is_verified := TRUE;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_review
  BEFORE INSERT ON reviews
  FOR EACH ROW EXECUTE FUNCTION validate_review_purchase();

CREATE OR REPLACE FUNCTION update_product_rating()
RETURNS TRIGGER AS $$
DECLARE
  v_product_id UUID;
BEGIN
  v_product_id := COALESCE(NEW.product_id, OLD.product_id);

  UPDATE products
  SET average_rating = (
    SELECT ROUND(AVG(rating)::NUMERIC, 2)
    FROM reviews
    WHERE product_id = v_product_id
  )
  WHERE id = v_product_id;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_rating_on_insert
  AFTER INSERT ON reviews
  FOR EACH ROW EXECUTE FUNCTION update_product_rating();

CREATE TRIGGER trg_update_rating_on_delete
  AFTER DELETE ON reviews
  FOR EACH ROW EXECUTE FUNCTION update_product_rating();

CREATE TRIGGER trg_update_rating_on_update
  AFTER UPDATE ON reviews
  FOR EACH ROW EXECUTE FUNCTION update_product_rating();

ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "reviews — public read"
  ON reviews FOR SELECT
  USING (TRUE);

CREATE POLICY "reviews — buyer creates own"
  ON reviews FOR INSERT
  WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "reviews — buyer updates own"
  ON reviews FOR UPDATE
  USING (auth.uid() = buyer_id)
  WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "reviews — buyer deletes own"
  ON reviews FOR DELETE
  USING (auth.uid() = buyer_id);

CREATE POLICY "reviews — admin full access"
  ON reviews FOR ALL
  USING (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));