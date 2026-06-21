CREATE TYPE product_type AS ENUM ('physical', 'digital');

CREATE TYPE product_status AS ENUM (
  'draft',           
  'pending_review', 
  'published',       
  'archived'         
);

CREATE TABLE products (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  seller_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,

  category_id     UUID REFERENCES categories(id) ON DELETE SET NULL,

  name            TEXT NOT NULL
                  CHECK (length(name) >= 3 AND length(name) <= 200),

  slug            TEXT NOT NULL UNIQUE,

  description     TEXT NOT NULL
                  CHECK (length(description) >= 10),

  price           NUMERIC(12, 2) NOT NULL CHECK (price > 0),

  commission_rate NUMERIC(5, 2) NOT NULL DEFAULT 10.00
                  CHECK (commission_rate >= 0.5 AND commission_rate <= 50),

  product_type    product_type NOT NULL DEFAULT 'physical',

  status          product_status NOT NULL DEFAULT 'draft',

  stock_count     INT NOT NULL DEFAULT 0 CHECK (stock_count >= 0),
  weight_grams    INT,                       -- for shipping calculation
  requires_shipping BOOLEAN NOT NULL DEFAULT TRUE,

  file_url        TEXT,
  file_size_mb    NUMERIC(8, 2),
  preview_url     TEXT,                      

  total_sales     INT NOT NULL DEFAULT 0,
  total_revenue   NUMERIC(14, 2) NOT NULL DEFAULT 0,
  average_rating  NUMERIC(3, 2),            

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT chk_digital_requires_file
    CHECK (
      product_type != 'digital' OR file_url IS NOT NULL
    ),
  CONSTRAINT chk_physical_requires_stock
    CHECK (
      product_type != 'physical' OR stock_count >= 0
    )
);

CREATE TRIGGER trg_update_products_updated_at
  BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_products_seller_status
  ON products(seller_id, status);

CREATE INDEX idx_products_status_created
  ON products(status, created_at DESC)
  WHERE status = 'published';

CREATE INDEX idx_products_category
  ON products(category_id, status)
  WHERE status = 'published';

CREATE INDEX idx_products_search
  ON products
  USING GIN (
    to_tsvector('french', name || ' ' || description)
  );

CREATE TABLE product_images (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  product_id  UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,

  url         TEXT NOT NULL,
  alt_text    TEXT,

  position    INT NOT NULL DEFAULT 0,

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_product_images_product
  ON product_images(product_id, position);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "products — public read published"
  ON products FOR SELECT
  USING (status = 'published');

CREATE POLICY "products — seller read own"
  ON products FOR SELECT
  USING (
    auth.uid() = seller_id
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'seller'
    )
  );

CREATE POLICY "products — seller create"
  ON products FOR INSERT
  WITH CHECK (
    auth.uid() = seller_id
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'seller'
    )
  );

CREATE POLICY "products — seller update own"
  ON products FOR UPDATE
  USING (
    auth.uid() = seller_id
    AND EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'seller'
    )
  )
  WITH CHECK (
    auth.uid() = seller_id
    AND status != 'published'
  );

CREATE POLICY "products — admin full access"
  ON products FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

ALTER TABLE product_images ENABLE ROW LEVEL SECURITY;

CREATE POLICY "product_images — public read"
  ON product_images FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM products
      WHERE id = product_images.product_id
        AND status = 'published'
    )
  );

CREATE POLICY "product_images — seller manages own"
  ON product_images FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM products
      WHERE id = product_images.product_id
        AND seller_id = auth.uid()
    )
  );