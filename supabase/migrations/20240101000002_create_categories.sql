CREATE TABLE categories (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  name        TEXT NOT NULL,

  slug        TEXT NOT NULL UNIQUE,

  parent_id   UUID REFERENCES categories(id) ON DELETE SET NULL,

  icon_url    TEXT,

  position    INT NOT NULL DEFAULT 0,

  is_active   BOOLEAN NOT NULL DEFAULT TRUE,

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── INDEXES ─────────────────────────────────────────────────────
CREATE INDEX idx_categories_parent ON categories(parent_id);

CREATE INDEX idx_categories_slug ON categories(slug);

ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "categories — public read"
  ON categories FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "categories — admin full access"
  ON categories FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

INSERT INTO categories (id, name, slug, position) VALUES
  (uuid_generate_v4(), 'Fashion & Clothing',      'fashion-clothing',      1),
  (uuid_generate_v4(), 'Beauty & Health',          'beauty-health',         2),
  (uuid_generate_v4(), 'Electronics',              'electronics',           3),
  (uuid_generate_v4(), 'Home & Kitchen',           'home-kitchen',          4),
  (uuid_generate_v4(), 'Sport & Leisure',          'sport-leisure',         5),
  (uuid_generate_v4(), 'Food & Nutrition',         'food-nutrition',        6),
  (uuid_generate_v4(), 'Kids & Baby',              'kids-baby',             7),
  (uuid_generate_v4(), 'Phones & Accessories',     'phones-accessories',    8),
  (uuid_generate_v4(), 'Digital Products',         'digital-products',      9),
  (uuid_generate_v4(), 'Education & Training',     'education-training',   10);