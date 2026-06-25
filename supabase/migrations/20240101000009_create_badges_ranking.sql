CREATE TYPE badge_type AS ENUM (
  'top_seller',
  'trending',
  'top_affiliated',
  'best_rated',
  'new_arrival'
);

CREATE TABLE product_badges (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id    UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  badge         badge_type NOT NULL,
  score         NUMERIC(14, 2) NOT NULL DEFAULT 0,
  rank_position INT,
  granted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '24 hours',
  CONSTRAINT uq_product_badge UNIQUE (product_id, badge)
);

CREATE INDEX idx_product_badges_active
  ON product_badges(badge, score DESC)
  WHERE expires_at > NOW();

CREATE INDEX idx_product_badges_product
  ON product_badges(product_id)
  WHERE expires_at > NOW();

ALTER TABLE product_badges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "product_badges — public read"
  ON product_badges FOR SELECT
  USING (expires_at > NOW());

CREATE POLICY "product_badges — admin full access"
  ON product_badges FOR ALL
  USING (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

CREATE MATERIALIZED VIEW top_products_ranking AS
WITH stats AS (
  SELECT
    p.id,
    p.name,
    p.slug,
    p.price,
    p.commission_rate,
    p.total_sales,
    p.total_revenue,
    p.average_rating,
    p.seller_id,
    p.category_id,
    p.product_type,
    COUNT(DISTINCT al.creator_id)
      FILTER (WHERE al.is_active = TRUE)           AS active_affiliates,
    COALESCE(SUM(al.clicks), 0)                    AS total_clicks,
    COALESCE(SUM(al.conversions), 0)               AS total_conversions,
    CASE
      WHEN COALESCE(SUM(al.clicks), 0) = 0 THEN 0
      ELSE ROUND(
        SUM(al.conversions)::NUMERIC / SUM(al.clicks) * 100, 2
      )
    END                                            AS conversion_rate,
    COUNT(DISTINCT oi.order_id) FILTER (
      WHERE o.created_at >= NOW() - INTERVAL '7 days'
        AND o.status NOT IN ('cancelled', 'refunded')
    )                                              AS sales_last_7d,
    ROUND(
      (p.total_sales * 0.40) +
      (COUNT(DISTINCT al.creator_id)
        FILTER (WHERE al.is_active) * 10 * 0.30) +
      (COALESCE(p.average_rating, 0) * 20 * 0.20) +
      (COUNT(DISTINCT oi.order_id) FILTER (
        WHERE o.created_at >= NOW() - INTERVAL '7 days'
          AND o.status NOT IN ('cancelled', 'refunded')
      ) * 5 * 0.10)
    , 2)                                           AS composite_score
  FROM products p
  LEFT JOIN affiliate_links al ON al.product_id = p.id
  LEFT JOIN order_items oi     ON oi.product_id = p.id
  LEFT JOIN orders o           ON o.id = oi.order_id
    AND o.status NOT IN ('cancelled', 'refunded')
  WHERE p.status = 'published'
  GROUP BY
    p.id, p.name, p.slug, p.price, p.commission_rate,
    p.total_sales, p.total_revenue, p.average_rating,
    p.seller_id, p.category_id, p.product_type
)
SELECT
  s.*,
  RANK() OVER (ORDER BY composite_score DESC)
    AS global_rank,
  RANK() OVER (
    PARTITION BY category_id ORDER BY composite_score DESC
  )                                              AS category_rank,
  RANK() OVER (
    ORDER BY active_affiliates DESC, conversion_rate DESC
  )                                              AS affiliation_rank,
  RANK() OVER (ORDER BY total_sales DESC)        AS sales_rank,
  RANK() OVER (
    ORDER BY sales_last_7d DESC, composite_score DESC
  )                                              AS trending_rank
FROM stats
WITH DATA;

CREATE UNIQUE INDEX idx_top_products_id
  ON top_products_ranking(id);

CREATE INDEX idx_top_products_global
  ON top_products_ranking(global_rank ASC);

CREATE INDEX idx_top_products_category
  ON top_products_ranking(category_id, category_rank ASC);

CREATE INDEX idx_top_products_affiliation
  ON top_products_ranking(affiliation_rank ASC);

CREATE INDEX idx_top_products_trending
  ON top_products_ranking(trending_rank ASC);

CREATE OR REPLACE FUNCTION refresh_top_products_ranking()
RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY top_products_ranking;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION refresh_creator_ranking()
RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY creator_monthly_ranking;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION compute_product_badges()
RETURNS void AS $$
BEGIN
  INSERT INTO product_badges (product_id, badge, score, rank_position, expires_at)
  SELECT
    id,
    'top_seller'::badge_type,
    total_sales,
    sales_rank,
    NOW() + INTERVAL '24 hours'
  FROM top_products_ranking
  WHERE sales_rank <= 10
  ON CONFLICT (product_id, badge)
  DO UPDATE SET
    score         = EXCLUDED.score,
    rank_position = EXCLUDED.rank_position,
    granted_at    = NOW(),
    expires_at    = NOW() + INTERVAL '24 hours';

  INSERT INTO product_badges (product_id, badge, score, rank_position, expires_at)
  SELECT
    id,
    'trending'::badge_type,
    sales_last_7d,
    trending_rank,
    NOW() + INTERVAL '24 hours'
  FROM top_products_ranking
  WHERE trending_rank <= 10
    AND sales_last_7d > 0
  ON CONFLICT (product_id, badge)
  DO UPDATE SET
    score         = EXCLUDED.score,
    rank_position = EXCLUDED.rank_position,
    granted_at    = NOW(),
    expires_at    = NOW() + INTERVAL '24 hours';

  INSERT INTO product_badges (product_id, badge, score, rank_position, expires_at)
  SELECT
    id,
    'top_affiliated'::badge_type,
    active_affiliates,
    affiliation_rank,
    NOW() + INTERVAL '24 hours'
  FROM top_products_ranking
  WHERE affiliation_rank <= 10
    AND active_affiliates > 0
  ON CONFLICT (product_id, badge)
  DO UPDATE SET
    score         = EXCLUDED.score,
    rank_position = EXCLUDED.rank_position,
    granted_at    = NOW(),
    expires_at    = NOW() + INTERVAL '24 hours';

  INSERT INTO product_badges (product_id, badge, score, rank_position, expires_at)
  SELECT
    p.id,
    'best_rated'::badge_type,
    p.average_rating,
    NULL,
    NOW() + INTERVAL '24 hours'
  FROM products p
  WHERE p.status    = 'published'
    AND p.average_rating >= 4.5
  ON CONFLICT (product_id, badge)
  DO UPDATE SET
    score      = EXCLUDED.score,
    granted_at = NOW(),
    expires_at = NOW() + INTERVAL '24 hours';

  INSERT INTO product_badges (product_id, badge, score, rank_position, expires_at)
  SELECT
    p.id,
    'new_arrival'::badge_type,
    EXTRACT(EPOCH FROM (NOW() - p.created_at)),
    NULL,
    NOW() + INTERVAL '24 hours'
  FROM products p
  WHERE p.status     = 'published'
    AND p.created_at >= NOW() - INTERVAL '7 days'
  ON CONFLICT (product_id, badge)
  DO UPDATE SET
    score      = EXCLUDED.score,
    granted_at = NOW(),
    expires_at = NOW() + INTERVAL '24 hours';

  DELETE FROM product_badges WHERE expires_at <= NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;