CREATE TYPE transaction_type AS ENUM (
  'payment_in',
  'platform_fee',
  'creator_payout',
  'seller_payout',
  'refund_buyer',
  'refund_platform'
);

CREATE TYPE transaction_status AS ENUM (
  'pending',
  'processing',
  'completed',
  'failed',
  'cancelled'
);

CREATE TYPE payout_status AS ENUM (
  'scheduled',
  'ready',
  'processing',
  'completed',
  'failed',
  'cancelled'
);

CREATE TYPE dispute_status AS ENUM (
  'open',
  'resolved',
  'rejected',
  'cancelled'
);

CREATE TYPE dispute_reason AS ENUM (
  'not_delivered',
  'wrong_item',
  'damaged',
  'not_as_described',
  'quality_issue'
);

CREATE TYPE notification_channel AS ENUM (
  'email',
  'whatsapp',
  'sms'
);

CREATE TYPE notification_status AS ENUM (
  'pending',
  'sent',
  'failed',
  'skipped'
);

CREATE TABLE payment_transactions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
  from_user_id    UUID REFERENCES profiles(id) ON DELETE SET NULL,
  to_user_id      UUID REFERENCES profiles(id) ON DELETE SET NULL,
  type            transaction_type NOT NULL,
  amount          NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  currency        TEXT NOT NULL DEFAULT 'XAF'
                  CHECK (currency IN ('XAF', 'XOF', 'USD', 'EUR')),
  status          transaction_status NOT NULL DEFAULT 'pending',
  psp_reference   TEXT UNIQUE,
  payment_method  TEXT,
  description     TEXT,
  metadata        JSONB NOT NULL DEFAULT '{}',
  scheduled_at    TIMESTAMPTZ,
  processed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_update_payment_transactions_updated_at
  BEFORE UPDATE ON payment_transactions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_payment_tx_order
  ON payment_transactions(order_id);

CREATE INDEX idx_payment_tx_to_user
  ON payment_transactions(to_user_id, created_at DESC);

CREATE INDEX idx_payment_tx_status
  ON payment_transactions(status, scheduled_at)
  WHERE status IN ('pending', 'processing');

CREATE TABLE escrow_holds (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id            UUID NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
  total_amount        NUMERIC(12, 2) NOT NULL CHECK (total_amount > 0),
  platform_amount     NUMERIC(12, 2) NOT NULL DEFAULT 0,
  creator_amount      NUMERIC(12, 2) NOT NULL DEFAULT 0,
  seller_amount       NUMERIC(12, 2) NOT NULL DEFAULT 0,
  held_amount         NUMERIC(12, 2) NOT NULL,
  status              TEXT NOT NULL DEFAULT 'holding'
                      CHECK (status IN ('holding', 'releasing', 'released', 'refunded')),
  creator_release_at  TIMESTAMPTZ,
  seller_release_at   TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_escrow_hold_order UNIQUE (order_id)
);

CREATE TRIGGER trg_update_escrow_holds_updated_at
  BEFORE UPDATE ON escrow_holds
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_escrow_holds_status
  ON escrow_holds(status);

CREATE INDEX idx_escrow_holds_release
  ON escrow_holds(creator_release_at, seller_release_at)
  WHERE status = 'holding';

CREATE TABLE payouts (
  id                        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  escrow_hold_id            UUID NOT NULL REFERENCES escrow_holds(id) ON DELETE RESTRICT,
  recipient_id              UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  order_id                  UUID NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
  recipient_type            TEXT NOT NULL
                            CHECK (recipient_type IN ('platform', 'creator', 'seller')),
  amount                    NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  currency                  TEXT NOT NULL DEFAULT 'XAF',
  status                    payout_status NOT NULL DEFAULT 'scheduled',
  delay_minutes             INT NOT NULL DEFAULT 0,
  scheduled_at              TIMESTAMPTZ,
  triggered_by              TEXT,
  recipient_payment_method  TEXT,
  recipient_payment_number  TEXT,
  psp_reference             TEXT,
  psp_response              JSONB NOT NULL DEFAULT '{}',
  executed_at               TIMESTAMPTZ,
  failure_reason            TEXT,
  retry_count               INT NOT NULL DEFAULT 0,
  created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_update_payouts_updated_at
  BEFORE UPDATE ON payouts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_payouts_ready
  ON payouts(scheduled_at, status)
  WHERE status IN ('scheduled', 'ready', 'failed');

CREATE INDEX idx_payouts_recipient
  ON payouts(recipient_id, status, created_at DESC);

CREATE INDEX idx_payouts_order
  ON payouts(order_id);

CREATE TABLE disputes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
  buyer_id        UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  seller_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
  reason          dispute_reason NOT NULL,
  description     TEXT NOT NULL CHECK (length(description) >= 20),
  evidence_urls   TEXT[] DEFAULT '{}',
  status          dispute_status NOT NULL DEFAULT 'open',
  resolution_note TEXT,
  resolved_by     UUID REFERENCES profiles(id) ON DELETE SET NULL,
  resolved_at     TIMESTAMPTZ,
  payout_deadline TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_dispute_order UNIQUE (order_id)
);

CREATE TRIGGER trg_update_disputes_updated_at
  BEFORE UPDATE ON disputes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_disputes_order  ON disputes(order_id);
CREATE INDEX idx_disputes_status ON disputes(status)
  WHERE status = 'open';

CREATE TABLE notification_queue (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  order_id      UUID REFERENCES orders(id) ON DELETE SET NULL,
  channel       notification_channel NOT NULL,
  recipient     TEXT NOT NULL,
  template      TEXT NOT NULL,
  payload       JSONB NOT NULL DEFAULT '{}',
  status        notification_status NOT NULL DEFAULT 'pending',
  sent_at       TIMESTAMPTZ,
  error_message TEXT,
  retry_count   INT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notif_queue_status
  ON notification_queue(status, created_at)
  WHERE status IN ('pending', 'failed');

CREATE INDEX idx_notif_queue_user
  ON notification_queue(user_id, created_at DESC);

CREATE OR REPLACE FUNCTION create_escrow_on_payment()
RETURNS TRIGGER AS $$
DECLARE
  v_platform_pct  NUMERIC := 0.05;
  v_creator_pct   NUMERIC := 0.10;
  v_seller_pct    NUMERIC;
  v_platform_amt  NUMERIC;
  v_creator_amt   NUMERIC;
  v_seller_amt    NUMERIC;
  v_hold_id       UUID;
  v_creator_id    UUID;
  v_buyer_name    TEXT;
  v_buyer_email   TEXT;
  v_buyer_phone   TEXT;
BEGIN
  IF NEW.payment_status = 'paid' AND OLD.payment_status != 'paid' THEN

    SELECT al.creator_id INTO v_creator_id
    FROM affiliate_links al
    WHERE al.id = NEW.affiliate_link_id;

    v_platform_amt := ROUND(NEW.total_amount * v_platform_pct, 2);

    IF v_creator_id IS NOT NULL THEN
      v_creator_amt := ROUND(NEW.total_amount * v_creator_pct, 2);
    ELSE
      v_creator_amt := 0;
      v_creator_pct := 0;
    END IF;

    v_seller_pct := 1 - v_platform_pct - v_creator_pct;
    v_seller_amt := NEW.total_amount - v_platform_amt - v_creator_amt;

    INSERT INTO escrow_holds (
      order_id, total_amount,
      platform_amount, creator_amount, seller_amount,
      held_amount, creator_release_at, seller_release_at
    ) VALUES (
      NEW.id, NEW.total_amount,
      v_platform_amt, v_creator_amt, v_seller_amt,
      NEW.total_amount,
      NOW() + INTERVAL '72 hours',
      NULL
    ) RETURNING id INTO v_hold_id;

    INSERT INTO payment_transactions (
      order_id, from_user_id, type, amount, status, description
    ) VALUES (
      NEW.id, NEW.buyer_id, 'payment_in',
      NEW.total_amount, 'completed',
      'Payment received — Order ' || LEFT(NEW.id::TEXT, 8)
    );

    INSERT INTO payouts (
      escrow_hold_id, recipient_id, order_id,
      recipient_type, amount, delay_minutes,
      scheduled_at, triggered_by
    ) VALUES (
      v_hold_id, NEW.seller_id, NEW.id,
      'platform', v_platform_amt, 0,
      NOW(), 'timer'
    );

    IF v_creator_id IS NOT NULL THEN
      INSERT INTO payouts (
        escrow_hold_id, recipient_id, order_id,
        recipient_type, amount, delay_minutes,
        scheduled_at, triggered_by,
        recipient_payment_method, recipient_payment_number
      )
      SELECT
        v_hold_id, v_creator_id, NEW.id,
        'creator', v_creator_amt, 4320,
        NOW() + INTERVAL '72 hours', 'timer',
        p.payment_method, p.payment_number
      FROM profiles p WHERE p.id = v_creator_id;
    END IF;

    INSERT INTO payouts (
      escrow_hold_id, recipient_id, order_id,
      recipient_type, amount, delay_minutes,
      scheduled_at, triggered_by,
      recipient_payment_method, recipient_payment_number
    )
    SELECT
      v_hold_id, NEW.seller_id, NEW.id,
      'seller', v_seller_amt, 0,
      NULL, 'delivery_confirmed',
      p.payment_method, p.payment_number
    FROM profiles p WHERE p.id = NEW.seller_id;

    SELECT name, email, phone
    INTO v_buyer_name, v_buyer_email, v_buyer_phone
    FROM profiles WHERE id = NEW.buyer_id;

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.buyer_id, NEW.id, 'email', v_buyer_email,
      'order_confirmed',
      jsonb_build_object(
        'buyer_name',   v_buyer_name,
        'order_id',     NEW.id,
        'order_short',  LEFT(NEW.id::TEXT, 8),
        'total_amount', NEW.total_amount,
        'currency',     'XAF'
      )
    );

    IF v_buyer_phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.buyer_id, NEW.id, 'whatsapp', v_buyer_phone,
        'order_confirmed_whatsapp',
        jsonb_build_object(
          'buyer_name',   v_buyer_name,
          'order_short',  LEFT(NEW.id::TEXT, 8),
          'total_amount', NEW.total_amount,
          'currency',     'XAF'
        )
      );
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_create_escrow_on_payment
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION create_escrow_on_payment();

CREATE OR REPLACE FUNCTION release_seller_payout_on_delivery()
RETURNS TRIGGER AS $$
DECLARE
  v_buyer_name  TEXT;
  v_buyer_email TEXT;
  v_buyer_phone TEXT;
  v_order_short TEXT;
BEGIN
  IF NEW.status = 'delivered' AND OLD.status != 'delivered' THEN

    UPDATE payouts
    SET
      scheduled_at = NOW() + INTERVAL '48 hours',
      status       = 'scheduled',
      triggered_by = 'delivery_confirmed'
    WHERE order_id       = NEW.id
      AND recipient_type = 'seller'
      AND status         = 'scheduled';

    UPDATE escrow_holds
    SET
      seller_release_at = NOW() + INTERVAL '48 hours',
      status            = 'releasing'
    WHERE order_id = NEW.id;

    SELECT name, email, phone
    INTO v_buyer_name, v_buyer_email, v_buyer_phone
    FROM profiles WHERE id = NEW.buyer_id;

    v_order_short := LEFT(NEW.id::TEXT, 8);

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.buyer_id, NEW.id, 'email', v_buyer_email,
      'order_delivered',
      jsonb_build_object(
        'buyer_name',    v_buyer_name,
        'order_id',      NEW.id,
        'order_short',   v_order_short,
        'total_amount',  NEW.total_amount,
        'currency',      'XAF',
        'dispute_hours', 48,
        'dispute_url',   'https://nelmark.cm/orders/' || NEW.id || '/dispute'
      )
    );

    IF v_buyer_phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.buyer_id, NEW.id, 'whatsapp', v_buyer_phone,
        'order_delivered_whatsapp',
        jsonb_build_object(
          'buyer_name',    v_buyer_name,
          'order_short',   v_order_short,
          'dispute_hours', 48,
          'dispute_url',   'https://nelmark.cm/orders/' || NEW.id || '/dispute'
        )
      );
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_release_seller_payout
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION release_seller_payout_on_delivery();

CREATE OR REPLACE FUNCTION cancel_payouts_on_cancellation()
RETURNS TRIGGER AS $$
DECLARE
  v_buyer_name  TEXT;
  v_buyer_email TEXT;
  v_buyer_phone TEXT;
BEGIN
  IF NEW.status = 'cancelled'
     AND OLD.status NOT IN ('delivered', 'cancelled', 'refunded')
  THEN
    UPDATE payouts
    SET status = 'cancelled'
    WHERE order_id = NEW.id
      AND status IN ('scheduled', 'ready');

    UPDATE escrow_holds
    SET status = 'refunded'
    WHERE order_id = NEW.id;

    INSERT INTO payment_transactions (
      order_id, to_user_id, type, amount, status, description
    ) VALUES (
      NEW.id, NEW.buyer_id, 'refund_buyer',
      NEW.total_amount, 'pending',
      'Refund — Cancelled order ' || LEFT(NEW.id::TEXT, 8)
    );

    SELECT name, email, phone
    INTO v_buyer_name, v_buyer_email, v_buyer_phone
    FROM profiles WHERE id = NEW.buyer_id;

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.buyer_id, NEW.id, 'email', v_buyer_email,
      'order_cancelled',
      jsonb_build_object(
        'buyer_name',   v_buyer_name,
        'order_short',  LEFT(NEW.id::TEXT, 8),
        'total_amount', NEW.total_amount,
        'currency',     'XAF'
      )
    );

    IF v_buyer_phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.buyer_id, NEW.id, 'whatsapp', v_buyer_phone,
        'order_cancelled_whatsapp',
        jsonb_build_object(
          'buyer_name',   v_buyer_name,
          'order_short',  LEFT(NEW.id::TEXT, 8),
          'total_amount', NEW.total_amount,
          'currency',     'XAF'
        )
      );
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_cancel_payouts
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION cancel_payouts_on_cancellation();

CREATE OR REPLACE FUNCTION suspend_payout_on_dispute()
RETURNS TRIGGER AS $$
DECLARE
  v_buyer_name   TEXT;
  v_buyer_email  TEXT;
  v_buyer_phone  TEXT;
  v_seller_name  TEXT;
  v_seller_email TEXT;
  v_order_short  TEXT;
BEGIN
  v_order_short := LEFT(NEW.order_id::TEXT, 8);

  SELECT name, email, phone
  INTO v_buyer_name, v_buyer_email, v_buyer_phone
  FROM profiles WHERE id = NEW.buyer_id;

  SELECT name, email
  INTO v_seller_name, v_seller_email
  FROM profiles WHERE id = NEW.seller_id;

  IF NEW.status = 'open' THEN
    UPDATE payouts
    SET status = 'scheduled'
    WHERE order_id       = NEW.order_id
      AND recipient_type = 'seller'
      AND status IN ('scheduled', 'ready');

    UPDATE commissions
    SET status = 'pending'
    WHERE order_id = NEW.order_id
      AND status   = 'approved';

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.seller_id, NEW.order_id, 'email', v_seller_email,
      'dispute_opened_seller',
      jsonb_build_object(
        'seller_name',  v_seller_name,
        'order_short',  v_order_short,
        'reason',       NEW.reason,
        'dispute_url',  'https://nelmark.cm/dashboard/seller/disputes/' || NEW.id
      )
    );
  END IF;

  IF NEW.status = 'resolved' AND OLD.status != 'resolved' THEN
    UPDATE payouts
    SET status = 'cancelled'
    WHERE order_id       = NEW.order_id
      AND recipient_type = 'seller'
      AND status NOT IN ('completed', 'cancelled');

    UPDATE commissions
    SET status = 'rejected', payment_note = 'Dispute resolved in buyer favor'
    WHERE order_id = NEW.order_id
      AND status NOT IN ('paid', 'rejected');

    INSERT INTO payment_transactions (
      order_id, to_user_id, type, amount, status, description
    )
    SELECT
      NEW.order_id, NEW.buyer_id, 'refund_buyer',
      o.total_amount, 'pending',
      'Refund — Dispute resolved — Order ' || v_order_short
    FROM orders o WHERE o.id = NEW.order_id;

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.buyer_id, NEW.order_id, 'email', v_buyer_email,
      'dispute_resolved_buyer',
      jsonb_build_object(
        'buyer_name',  v_buyer_name,
        'order_short', v_order_short,
        'note',        NEW.resolution_note
      )
    );

    IF v_buyer_phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.buyer_id, NEW.order_id, 'whatsapp', v_buyer_phone,
        'dispute_resolved_whatsapp',
        jsonb_build_object(
          'buyer_name',  v_buyer_name,
          'order_short', v_order_short
        )
      );
    END IF;
  END IF;

  IF NEW.status = 'rejected' AND OLD.status != 'rejected' THEN
    UPDATE payouts
    SET scheduled_at = NOW(), status = 'ready'
    WHERE order_id       = NEW.order_id
      AND recipient_type = 'seller'
      AND status         = 'scheduled';

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.buyer_id, NEW.order_id, 'email', v_buyer_email,
      'dispute_rejected_buyer',
      jsonb_build_object(
        'buyer_name',  v_buyer_name,
        'order_short', v_order_short,
        'note',        NEW.resolution_note
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_suspend_payout_on_dispute
  AFTER INSERT OR UPDATE ON disputes
  FOR EACH ROW EXECUTE FUNCTION suspend_payout_on_dispute();

ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payment_transactions — user sees own"
  ON payment_transactions FOR SELECT
  USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);

CREATE POLICY "payment_transactions — admin full access"
  ON payment_transactions FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

ALTER TABLE escrow_holds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "escrow_holds — seller reads own"
  ON escrow_holds FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM orders o
    WHERE o.id = escrow_holds.order_id AND o.seller_id = auth.uid()
  ));

CREATE POLICY "escrow_holds — admin full access"
  ON escrow_holds FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

ALTER TABLE payouts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payouts — recipient reads own"
  ON payouts FOR SELECT
  USING (auth.uid() = recipient_id);

CREATE POLICY "payouts — admin full access"
  ON payouts FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

ALTER TABLE disputes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "disputes — buyer manages own"
  ON disputes FOR ALL
  USING (auth.uid() = buyer_id)
  WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "disputes — seller reads own"
  ON disputes FOR SELECT
  USING (auth.uid() = seller_id);

CREATE POLICY "disputes — admin full access"
  ON disputes FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

ALTER TABLE notification_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notification_queue — user reads own"
  ON notification_queue FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "notification_queue — admin full access"
  ON notification_queue FOR ALL
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));