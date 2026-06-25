CREATE TABLE app_config (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  description TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_update_app_config_updated_at
  BEFORE UPDATE ON app_config
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "app_config — public read"
  ON app_config FOR SELECT
  USING (TRUE);

CREATE POLICY "app_config — admin full access"
  ON app_config FOR ALL
  USING (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

INSERT INTO app_config (key, value, description) VALUES
  ('app_url',                  'https://nelmark.cm',        'URL principale de la plateforme'),
  ('support_email',            'support@nelmark.cm',         'Email du support client'),
  ('support_url',              'https://nelmark.cm/support', 'Page support'),
  ('admin_email',              'admin@nelmark.cm',           'Email admin par défaut'),
  ('commission_platform_rate', '0.05',                       'Taux commission plateforme (5%)'),
  ('commission_creator_rate',  '0.10',                       'Taux commission créateur (10%)'),
  ('payout_delay_hours',       '72',                         'Délai anti-fraude créateur en heures'),
  ('dispute_window_hours',     '48',                         'Fenêtre contestation livraison en heures'),
  ('low_stock_threshold',      '5',                          'Seuil alerte stock faible'),
  ('max_payout_retries',       '3',                          'Nombre max de tentatives payout'),
  ('affiliate_cookie_days',    '30',                         'Durée du cookie affilié en jours'),
  ('fraud_click_threshold',    '3',                          'Nb clics suspects avant flag fraude'),
  ('fraud_window_minutes',     '60',                         'Fenêtre de détection fraude en minutes'),
  ('min_commission_rate',      '0.5',                        'Taux commission minimum vendeur (%)'),
  ('max_commission_rate',      '50',                         'Taux commission maximum vendeur (%)');

CREATE OR REPLACE FUNCTION get_config(p_key TEXT)
RETURNS TEXT AS $$
  SELECT value FROM app_config WHERE key = p_key;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION notify_seller_new_order()
RETURNS TRIGGER AS $$
DECLARE
  v_seller_name  TEXT;
  v_seller_email TEXT;
  v_seller_phone TEXT;
  v_order_short  TEXT;
  v_app_url      TEXT;
BEGIN
  IF NEW.status = 'confirmed' AND OLD.status != 'confirmed' THEN

    SELECT name, email, phone
    INTO v_seller_name, v_seller_email, v_seller_phone
    FROM profiles WHERE id = NEW.seller_id;

    v_order_short := LEFT(NEW.id::TEXT, 8);
    v_app_url     := get_config('app_url');

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.seller_id, NEW.id, 'email', v_seller_email,
      'new_order_seller',
      jsonb_build_object(
        'seller_name',  v_seller_name,
        'order_short',  v_order_short,
        'order_id',     NEW.id,
        'total_amount', NEW.total_amount,
        'currency',     'XAF',
        'dashboard_url', v_app_url || '/dashboard/seller/orders/' || NEW.id
      )
    );

    IF v_seller_phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.seller_id, NEW.id, 'whatsapp', v_seller_phone,
        'new_order_seller_whatsapp',
        jsonb_build_object(
          'seller_name',  v_seller_name,
          'order_short',  v_order_short,
          'total_amount', NEW.total_amount,
          'currency',     'XAF',
          'dashboard_url', v_app_url || '/dashboard/seller/orders/' || NEW.id
        )
      );
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_seller_new_order
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION notify_seller_new_order();

CREATE OR REPLACE FUNCTION notify_buyer_order_shipped()
RETURNS TRIGGER AS $$
DECLARE
  v_buyer_name  TEXT;
  v_buyer_email TEXT;
  v_buyer_phone TEXT;
  v_order_short TEXT;
  v_app_url     TEXT;
BEGIN
  IF NEW.status = 'shipped' AND OLD.status != 'shipped' THEN

    SELECT name, email, phone
    INTO v_buyer_name, v_buyer_email, v_buyer_phone
    FROM profiles WHERE id = NEW.buyer_id;

    v_order_short := LEFT(NEW.id::TEXT, 8);
    v_app_url     := get_config('app_url');

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.buyer_id, NEW.id, 'email', v_buyer_email,
      'order_shipped',
      jsonb_build_object(
        'buyer_name',   v_buyer_name,
        'order_short',  v_order_short,
        'order_id',     NEW.id,
        'tracking_url', v_app_url || '/orders/' || NEW.id
      )
    );

    IF v_buyer_phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.buyer_id, NEW.id, 'whatsapp', v_buyer_phone,
        'order_shipped_whatsapp',
        jsonb_build_object(
          'buyer_name',   v_buyer_name,
          'order_short',  v_order_short,
          'tracking_url', v_app_url || '/orders/' || NEW.id
        )
      );
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_buyer_order_shipped
  AFTER UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION notify_buyer_order_shipped();

CREATE OR REPLACE FUNCTION notify_payout_completed()
RETURNS TRIGGER AS $$
DECLARE
  v_recipient_name  TEXT;
  v_recipient_email TEXT;
  v_recipient_phone TEXT;
  v_app_url         TEXT;
BEGIN
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN

    SELECT name, email, phone
    INTO v_recipient_name, v_recipient_email, v_recipient_phone
    FROM profiles WHERE id = NEW.recipient_id;

    v_app_url := get_config('app_url');

    IF NEW.recipient_type = 'seller' THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.recipient_id, NEW.order_id, 'email', v_recipient_email,
        'seller_paid',
        jsonb_build_object(
          'seller_name',   v_recipient_name,
          'amount',        NEW.amount,
          'currency',      NEW.currency,
          'order_id',      NEW.order_id,
          'psp_reference', NEW.psp_reference,
          'dashboard_url', v_app_url || '/dashboard/seller'
        )
      );

      IF v_recipient_phone IS NOT NULL THEN
        INSERT INTO notification_queue (
          user_id, order_id, channel, recipient, template, payload
        ) VALUES (
          NEW.recipient_id, NEW.order_id, 'whatsapp', v_recipient_phone,
          'seller_paid_whatsapp',
          jsonb_build_object(
            'seller_name', v_recipient_name,
            'amount',      NEW.amount,
            'currency',    NEW.currency
          )
        );
      END IF;
    END IF;

    IF NEW.recipient_type = 'creator' THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.recipient_id, NEW.order_id, 'email', v_recipient_email,
        'commission_paid',
        jsonb_build_object(
          'creator_name',  v_recipient_name,
          'amount',        NEW.amount,
          'currency',      NEW.currency,
          'order_id',      NEW.order_id,
          'psp_reference', NEW.psp_reference,
          'dashboard_url', v_app_url || '/dashboard/creator'
        )
      );

      IF v_recipient_phone IS NOT NULL THEN
        INSERT INTO notification_queue (
          user_id, order_id, channel, recipient, template, payload
        ) VALUES (
          NEW.recipient_id, NEW.order_id, 'whatsapp', v_recipient_phone,
          'commission_paid_whatsapp',
          jsonb_build_object(
            'creator_name', v_recipient_name,
            'amount',       NEW.amount,
            'currency',     NEW.currency
          )
        );
      END IF;
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_payout_completed
  AFTER UPDATE ON payouts
  FOR EACH ROW EXECUTE FUNCTION notify_payout_completed();

CREATE OR REPLACE FUNCTION notify_payout_failed()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
  v_app_url     TEXT;
BEGIN
  IF NEW.status = 'failed'
     AND NEW.retry_count >= get_config('max_payout_retries')::INT
  THEN
    v_admin_email := get_config('admin_email');
    v_app_url     := get_config('app_url');

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.recipient_id, NEW.order_id, 'email', v_admin_email,
      'payout_failed',
      jsonb_build_object(
        'payout_id',      NEW.id,
        'recipient_type', NEW.recipient_type,
        'amount',         NEW.amount,
        'currency',       NEW.currency,
        'failure_reason', NEW.failure_reason,
        'retry_count',    NEW.retry_count,
        'admin_url',      v_app_url || '/dashboard/admin/payouts/' || NEW.id
      )
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_payout_failed
  AFTER UPDATE ON payouts
  FOR EACH ROW EXECUTE FUNCTION notify_payout_failed();

CREATE OR REPLACE FUNCTION notify_commission_earned()
RETURNS TRIGGER AS $$
DECLARE
  v_creator_name  TEXT;
  v_creator_email TEXT;
  v_creator_phone TEXT;
  v_product_name  TEXT;
  v_order_short   TEXT;
  v_app_url       TEXT;
BEGIN
  SELECT name, email, phone
  INTO v_creator_name, v_creator_email, v_creator_phone
  FROM profiles WHERE id = NEW.creator_id;

  SELECT p.name INTO v_product_name
  FROM order_items oi
  JOIN products p ON p.id = oi.product_id
  WHERE oi.id = NEW.order_item_id;

  v_order_short := LEFT(NEW.order_id::TEXT, 8);
  v_app_url     := get_config('app_url');

  INSERT INTO notification_queue (
    user_id, order_id, channel, recipient, template, payload
  ) VALUES (
    NEW.creator_id, NEW.order_id, 'email', v_creator_email,
    'commission_earned',
    jsonb_build_object(
      'creator_name',  v_creator_name,
      'amount',        NEW.amount,
      'currency',      'XAF',
      'product_name',  v_product_name,
      'order_short',   v_order_short,
      'dashboard_url', v_app_url || '/dashboard/creator'
    )
  );

  IF v_creator_phone IS NOT NULL THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.creator_id, NEW.order_id, 'whatsapp', v_creator_phone,
      'commission_earned_whatsapp',
      jsonb_build_object(
        'creator_name', v_creator_name,
        'amount',       NEW.amount,
        'currency',     'XAF',
        'product_name', v_product_name,
        'order_short',  v_order_short
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_commission_earned
  AFTER INSERT ON commissions
  FOR EACH ROW EXECUTE FUNCTION notify_commission_earned();

CREATE OR REPLACE FUNCTION notify_commission_rejected()
RETURNS TRIGGER AS $$
DECLARE
  v_creator_name  TEXT;
  v_creator_email TEXT;
  v_creator_phone TEXT;
  v_order_short   TEXT;
  v_app_url       TEXT;
BEGIN
  IF NEW.status = 'rejected' AND OLD.status != 'rejected' THEN

    SELECT name, email, phone
    INTO v_creator_name, v_creator_email, v_creator_phone
    FROM profiles WHERE id = NEW.creator_id;

    v_order_short := LEFT(NEW.order_id::TEXT, 8);
    v_app_url     := get_config('app_url');

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.creator_id, NEW.order_id, 'email', v_creator_email,
      'commission_rejected',
      jsonb_build_object(
        'creator_name',  v_creator_name,
        'amount',        NEW.amount,
        'currency',      'XAF',
        'order_short',   v_order_short,
        'note',          COALESCE(NEW.payment_note, 'Order cancelled'),
        'dashboard_url', v_app_url || '/dashboard/creator'
      )
    );

    IF v_creator_phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.creator_id, NEW.order_id, 'whatsapp', v_creator_phone,
        'commission_rejected_whatsapp',
        jsonb_build_object(
          'creator_name', v_creator_name,
          'amount',       NEW.amount,
          'currency',     'XAF',
          'order_short',  v_order_short
        )
      );
    END IF;

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_commission_rejected
  AFTER UPDATE ON commissions
  FOR EACH ROW EXECUTE FUNCTION notify_commission_rejected();

CREATE OR REPLACE FUNCTION notify_product_status_change()
RETURNS TRIGGER AS $$
DECLARE
  v_seller_name  TEXT;
  v_seller_email TEXT;
  v_seller_phone TEXT;
  v_app_url      TEXT;
  v_threshold    INT;
BEGIN
  SELECT name, email, phone
  INTO v_seller_name, v_seller_email, v_seller_phone
  FROM profiles WHERE id = NEW.seller_id;

  v_app_url   := get_config('app_url');
  v_threshold := get_config('low_stock_threshold')::INT;

  IF NEW.status = 'published' AND OLD.status != 'published' THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.seller_id, NULL, 'email', v_seller_email,
      'product_approved',
      jsonb_build_object(
        'seller_name',  v_seller_name,
        'product_name', NEW.name,
        'product_url',  v_app_url || '/products/' || NEW.slug,
        'dashboard_url', v_app_url || '/dashboard/seller/products'
      )
    );
  END IF;

  IF NEW.status = 'archived' AND OLD.status = 'pending_review' THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.seller_id, NULL, 'email', v_seller_email,
      'product_rejected',
      jsonb_build_object(
        'seller_name',   v_seller_name,
        'product_name',  NEW.name,
        'dashboard_url', v_app_url || '/dashboard/seller/products/' || NEW.id
      )
    );
  END IF;

  IF NEW.stock_count < v_threshold
     AND OLD.stock_count >= v_threshold
     AND NEW.product_type = 'physical'
  THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.seller_id, NULL, 'email', v_seller_email,
      'low_stock_alert',
      jsonb_build_object(
        'seller_name',   v_seller_name,
        'product_name',  NEW.name,
        'stock_count',   NEW.stock_count,
        'threshold',     v_threshold,
        'dashboard_url', v_app_url || '/dashboard/seller/products/' || NEW.id
      )
    );

    IF v_seller_phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.seller_id, NULL, 'whatsapp', v_seller_phone,
        'low_stock_alert_whatsapp',
        jsonb_build_object(
          'seller_name',  v_seller_name,
          'product_name', NEW.name,
          'stock_count',  NEW.stock_count
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_product_status
  AFTER UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION notify_product_status_change();

CREATE OR REPLACE FUNCTION notify_welcome_and_admin()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
  v_app_url     TEXT;
BEGIN
  v_admin_email := get_config('admin_email');
  v_app_url     := get_config('app_url');

  INSERT INTO notification_queue (
    user_id, order_id, channel, recipient, template, payload
  ) VALUES (
    NEW.id, NULL, 'email', NEW.email,
    'welcome',
    jsonb_build_object(
      'user_name',    NEW.name,
      'role',         NEW.role,
      'app_url',      v_app_url,
      'support_url',  get_config('support_url')
    )
  );

  IF NEW.role = 'seller' THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.id, NULL, 'email', v_admin_email,
      'new_seller_signup',
      jsonb_build_object(
        'seller_name',  NEW.name,
        'seller_email', NEW.email,
        'admin_url',    v_app_url || '/dashboard/admin/sellers/' || NEW.id
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_welcome
  AFTER INSERT ON profiles
  FOR EACH ROW EXECUTE FUNCTION notify_welcome_and_admin();

CREATE OR REPLACE FUNCTION notify_account_changes()
RETURNS TRIGGER AS $$
DECLARE
  v_app_url TEXT;
BEGIN
  v_app_url := get_config('app_url');

  IF NEW.is_active = FALSE AND OLD.is_active = TRUE THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.id, NULL, 'email', NEW.email,
      'account_suspended',
      jsonb_build_object(
        'user_name',   NEW.name,
        'support_url', get_config('support_url')
      )
    );
  END IF;

  IF NEW.is_verified = TRUE AND OLD.is_verified = FALSE THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.id, NULL, 'email', NEW.email,
      'seller_verified',
      jsonb_build_object(
        'seller_name',   NEW.name,
        'dashboard_url', v_app_url || '/dashboard/seller'
      )
    );

    IF NEW.phone IS NOT NULL THEN
      INSERT INTO notification_queue (
        user_id, order_id, channel, recipient, template, payload
      ) VALUES (
        NEW.id, NULL, 'whatsapp', NEW.phone,
        'seller_verified_whatsapp',
        jsonb_build_object(
          'seller_name',   NEW.name,
          'dashboard_url', v_app_url || '/dashboard/seller'
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_account_changes
  AFTER UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION notify_account_changes();

CREATE OR REPLACE FUNCTION notify_admin_product_pending()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
  v_app_url     TEXT;
BEGIN
  IF NEW.status = 'pending_review' AND OLD.status != 'pending_review' THEN

    v_admin_email := get_config('admin_email');
    v_app_url     := get_config('app_url');

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.seller_id, NULL, 'email', v_admin_email,
      'product_pending_review',
      jsonb_build_object(
        'product_name', NEW.name,
        'seller_id',    NEW.seller_id,
        'admin_url',    v_app_url || '/dashboard/admin/products/' || NEW.id
      )
    );

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_admin_product_pending
  AFTER UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION notify_admin_product_pending();

CREATE OR REPLACE FUNCTION notify_admin_suspicious_commission()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
  v_app_url     TEXT;
BEGIN
  IF NEW.is_suspicious = TRUE THEN

    v_admin_email := get_config('admin_email');
    v_app_url     := get_config('app_url');

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.creator_id, NEW.order_id, 'email', v_admin_email,
      'suspicious_commission',
      jsonb_build_object(
        'commission_id', NEW.id,
        'creator_id',    NEW.creator_id,
        'order_id',      NEW.order_id,
        'amount',        NEW.amount,
        'currency',      'XAF',
        'admin_url',     v_app_url || '/dashboard/admin/commissions/' || NEW.id
      )
    );

  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_admin_suspicious_commission
  AFTER INSERT ON commissions
  FOR EACH ROW EXECUTE FUNCTION notify_admin_suspicious_commission();

CREATE OR REPLACE FUNCTION notify_admin_new_dispute()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
  v_app_url     TEXT;
BEGIN
  v_admin_email := get_config('admin_email');
  v_app_url     := get_config('app_url');

  INSERT INTO notification_queue (
    user_id, order_id, channel, recipient, template, payload
  ) VALUES (
    NEW.buyer_id, NEW.order_id, 'email', v_admin_email,
    'dispute_admin_alert',
    jsonb_build_object(
      'dispute_id', NEW.id,
      'order_id',   NEW.order_id,
      'reason',     NEW.reason,
      'admin_url',  v_app_url || '/dashboard/admin/disputes/' || NEW.id
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_admin_new_dispute
  AFTER INSERT ON disputes
  FOR EACH ROW EXECUTE FUNCTION notify_admin_new_dispute();