CREATE TYPE onboarding_status AS ENUM (
  'pending',    -- pas encore commencé
  'in_progress',-- en cours
  'completed',  -- terminé
  'rejected'    -- rejeté par admin (seller uniquement)
);


CREATE TABLE creator_profiles (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id        UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  bio               TEXT CHECK (length(bio) <= 200),
  avatar_url        TEXT,
  social_links      JSONB NOT NULL DEFAULT '[]',
  country           TEXT NOT NULL DEFAULT 'CM',
  onboarding_status onboarding_status NOT NULL DEFAULT 'pending',
  completed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_update_creator_profiles_updated_at
  BEFORE UPDATE ON creator_profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE creator_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "creator_profiles — creator reads and updates own"
  ON creator_profiles FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = creator_profiles.profile_id
        AND id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = creator_profiles.profile_id
        AND id = auth.uid()
    )
  );

CREATE POLICY "creator_profiles — public read completed"
  ON creator_profiles FOR SELECT
  USING (onboarding_status = 'completed');

CREATE POLICY "creator_profiles — admin full access"
  ON creator_profiles FOR ALL
  USING (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

CREATE TABLE seller_profiles (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id          UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,

  shop_name           TEXT NOT NULL CHECK (length(shop_name) >= 2),
  shop_slug           TEXT NOT NULL UNIQUE,
  shop_description    TEXT NOT NULL CHECK (length(shop_description) >= 50),
  shop_logo_url       TEXT,
  shop_banner_url     TEXT,

  category_id         UUID REFERENCES categories(id) ON DELETE SET NULL,
  country             TEXT NOT NULL DEFAULT 'CM',
  city                TEXT NOT NULL,

  -- Type de produits vendus
  sells_physical      BOOLEAN NOT NULL DEFAULT TRUE,
  sells_digital       BOOLEAN NOT NULL DEFAULT FALSE,

  -- KYC — documents d'identité
  id_document_url     TEXT,
  id_document_type    TEXT CHECK (id_document_type IN ('cni', 'passport', 'residence_permit')),
  id_holder_name      TEXT,

  -- Métriques boutique (dénormalisées)
  total_products      INT NOT NULL DEFAULT 0,
  total_sales         INT NOT NULL DEFAULT 0,
  average_rating      NUMERIC(3, 2),

  onboarding_status   onboarding_status NOT NULL DEFAULT 'pending',
  onboarding_step     INT NOT NULL DEFAULT 1 CHECK (onboarding_step BETWEEN 1 AND 3),
  rejection_reason    TEXT,
  completed_at        TIMESTAMPTZ,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_update_seller_profiles_updated_at
  BEFORE UPDATE ON seller_profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_seller_profiles_slug
  ON seller_profiles(shop_slug);

CREATE INDEX idx_seller_profiles_status
  ON seller_profiles(onboarding_status);

ALTER TABLE seller_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "seller_profiles — public read completed"
  ON seller_profiles FOR SELECT
  USING (onboarding_status = 'completed');

CREATE POLICY "seller_profiles — seller manages own"
  ON seller_profiles FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = seller_profiles.profile_id
        AND id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = seller_profiles.profile_id
        AND id = auth.uid()
    )
  );

CREATE POLICY "seller_profiles — admin full access"
  ON seller_profiles FOR ALL
  USING (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

-- Trigger : auto-créer le profil étendu après inscription
CREATE OR REPLACE FUNCTION create_extended_profile()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role = 'creator' THEN
    INSERT INTO creator_profiles (profile_id)
    VALUES (NEW.id);
  END IF;

  IF NEW.role = 'seller' THEN
    INSERT INTO seller_profiles (
      profile_id,
      shop_name,
      shop_slug,
      shop_description,
      city
    ) VALUES (
      NEW.id,
      NEW.name || '''s Shop',
      LOWER(REGEXP_REPLACE(NEW.name, '[^a-zA-Z0-9]', '-', 'g'))
        || '-' || LEFT(NEW.id::TEXT, 6),
      'Welcome to my shop',
      'Non renseignée'
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_create_extended_profile
  AFTER INSERT ON profiles
  FOR EACH ROW EXECUTE FUNCTION create_extended_profile();

-- Trigger : notifier admin quand onboarding seller est soumis
CREATE OR REPLACE FUNCTION notify_admin_seller_onboarding()
RETURNS TRIGGER AS $$
DECLARE
  v_admin_email TEXT;
  v_app_url     TEXT;
  v_seller_name TEXT;
BEGIN
  IF NEW.onboarding_status = 'in_progress'
     AND NEW.onboarding_step = 3
     AND OLD.onboarding_step = 2
  THEN
    v_admin_email := get_config('admin_email');
    v_app_url     := get_config('app_url');

    SELECT name INTO v_seller_name
    FROM profiles WHERE id = NEW.profile_id;

    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    ) VALUES (
      NEW.profile_id, NULL, 'email', v_admin_email,
      'seller_onboarding_submitted',
      jsonb_build_object(
        'seller_name',    v_seller_name,
        'shop_name',      NEW.shop_name,
        'country',        NEW.country,
        'admin_url',      v_app_url || '/dashboard/admin/sellers/' || NEW.profile_id
      )
    );
  END IF;

  -- Notifier le vendeur si rejeté
  IF NEW.onboarding_status = 'rejected'
     AND OLD.onboarding_status != 'rejected'
  THEN
    INSERT INTO notification_queue (
      user_id, order_id, channel, recipient, template, payload
    )
    SELECT
      NEW.profile_id, NULL, 'email', p.email,
      'seller_onboarding_rejected',
      jsonb_build_object(
        'seller_name',     p.name,
        'rejection_reason', COALESCE(NEW.rejection_reason, 'Documents insuffisants'),
        'app_url',         get_config('app_url') || '/onboarding/seller'
      )
    FROM profiles p WHERE p.id = NEW.profile_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_notify_seller_onboarding
  AFTER UPDATE ON seller_profiles
  FOR EACH ROW EXECUTE FUNCTION notify_admin_seller_onboarding();