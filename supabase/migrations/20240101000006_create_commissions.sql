
CREATE TYPE commission_status AS ENUM (
  'pending',       
  'pending_review',
  'approved',      
  'paid',          
  'rejected'       
);

CREATE TABLE commissions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  creator_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  order_id        UUID NOT NULL REFERENCES orders(id)   ON DELETE RESTRICT,
  order_item_id   UUID NOT NULL REFERENCES order_items(id) ON DELETE RESTRICT,

  amount          NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  status          commission_status NOT NULL DEFAULT 'pending',

  payable_after   TIMESTAMPTZ NOT NULL
                  DEFAULT NOW() + INTERVAL '7 days',

  paid_at         TIMESTAMPTZ,
  payment_ref     TEXT,
  payment_note    TEXT,

  is_suspicious   BOOLEAN NOT NULL DEFAULT FALSE,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_commission_order_item UNIQUE (order_item_id)
);

CREATE TRIGGER trg_update_commissions_updated_at
  BEFORE UPDATE ON commissions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_commissions_creator
  ON commissions(creator_id, status);

CREATE INDEX idx_commissions_ready_to_pay
  ON commissions(payable_after, status)
  WHERE status = 'approved';

CREATE INDEX idx_commissions_order
  ON commissions(order_id);

CREATE OR REPLACE FUNCTION create_commissions_on_confirmation()
RETURNS TRIGGER AS $$
DECLARE
  v_creator_id    UUID;
  v_is_suspicious BOOLEAN;
BEGIN
  IF NEW.status = 'confirmed'
     AND OLD.status != 'confirmed'
     AND NEW.affiliate_link_id IS NOT NULL
  THEN
    SELECT creator_id INTO v_creator_id
    FROM affiliate_links
    WHERE id = NEW.affiliate_link_id;

    v_is_suspicious := (v_creator_id = NEW.buyer_id);

    INSERT INTO commissions (
      creator_id,
      order_id,
      order_item_id,
      amount,
      status,
      is_suspicious,
      payable_after
    )
    SELECT
      v_creator_id,
      NEW.id,
      oi.id,
      ROUND(oi.unit_price * oi.quantity * oi.commission_rate / 100, 2),
      CASE WHEN v_is_suspicious THEN 'pending_review'::commission_status
           ELSE 'pending'::commission_status
      END,
      v_is_suspicious,
      NOW() + INTERVAL '7 days'
    FROM order_items oi
    WHERE oi.order_id = NEW.id;

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_create_commissions
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION create_commissions_on_confirmation();

CREATE OR REPLACE FUNCTION approve_commissions_on_delivery()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN
    UPDATE commissions
    SET status = 'approved'
    WHERE order_id = NEW.id
      AND status = 'pending'
      AND payable_after <= NOW()
      AND is_suspicious = FALSE;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_approve_commissions
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION approve_commissions_on_delivery();

CREATE OR REPLACE FUNCTION reject_commissions_on_cancellation()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'cancelled'
     AND OLD.status NOT IN ('delivered', 'cancelled', 'refunded')
  THEN
    UPDATE commissions
    SET
      status       = 'rejected',
      payment_note = 'Order cancelled'
    WHERE order_id = NEW.id
      AND status IN ('pending', 'pending_review', 'approved');
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reject_commissions
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION reject_commissions_on_cancellation();

ALTER TABLE commissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "commissions — creator reads own"
  ON commissions FOR SELECT
  USING (auth.uid() = creator_id);

CREATE POLICY "commissions — admin full access"
  ON commissions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE MATERIALIZED VIEW creator_monthly_ranking AS
SELECT
  p.id              AS creator_id,
  p.name            AS creator_name,
  p.avatar_url,
  DATE_TRUNC('month', c.created_at) AS month,
  COUNT(DISTINCT c.order_id)        AS total_orders,
  SUM(c.amount)                     AS total_commissions,
  COUNT(c.id)                       AS commission_count,
  RANK() OVER (
    PARTITION BY DATE_TRUNC('month', c.created_at)
    ORDER BY SUM(c.amount) DESC
  ) AS rank
FROM commissions c
JOIN profiles p ON p.id = c.creator_id
WHERE c.status IN ('approved', 'paid')
GROUP BY
  p.id,
  p.name,
  p.avatar_url,
  DATE_TRUNC('month', c.created_at)
WITH DATA;

CREATE UNIQUE INDEX idx_ranking_creator_month
  ON creator_monthly_ranking(creator_id, month);

CREATE INDEX idx_ranking_month_rank
  ON creator_monthly_ranking(month DESC, rank ASC);