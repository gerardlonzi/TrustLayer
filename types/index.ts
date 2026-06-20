export type UserRole = 'buyer' | 'seller' | 'creator' | 'admin'

export type ProductStatus = 'draft' | 'pending_review' | 'published' | 'archived'

export type OrderStatus =
  | 'pending'
  | 'confirmed'
  | 'processing'
  | 'shipped'
  | 'delivered'
  | 'cancelled'
  | 'refunded'

export type PaymentStatus = 'pending' | 'paid' | 'failed' | 'refunded'

export type CommissionStatus = 'pending' | 'approved' | 'paid' | 'rejected'

export type PayoutStatus =
  | 'scheduled'
  | 'ready'
  | 'processing'
  | 'completed'
  | 'failed'
  | 'cancelled'

export type TransactionType =
  | 'payment_in'
  | 'platform_fee'
  | 'creator_payout'
  | 'seller_payout'
  | 'refund_buyer'
  | 'refund_platform'

export type TransactionStatus = 'pending' | 'processing' | 'completed' | 'failed' | 'cancelled'

export type BadgeType =
  | 'top_seller'
  | 'trending'
  | 'top_affiliated'
  | 'best_rated'
  | 'new_arrival'

export type Currency = 'XAF' | 'XOF' | 'USD' | 'EUR'

export type PaymentMethod = 'mtn_momo' | 'orange_money' | 'card' | 'bank_transfer'

export type RecipientType = 'platform' | 'creator' | 'seller'


export interface User {
  id: string
  email: string
  role: UserRole
  name: string
  avatar_url?: string
  phone?: string
  is_verified: boolean
  is_active: boolean
  payment_method?: PaymentMethod
  payment_number?: string
  created_at: string
  updated_at: string
}

export interface Category {
  id: string
  name: string
  slug: string
  parent_id?: string
  icon_url?: string
  position: number
  is_active: boolean
}

export interface Product {
  id: string
  seller_id: string
  category_id?: string
  name: string
  slug: string
  description: string
  price: number
  commission_rate: number
  status: ProductStatus
  stock_count: number
  total_sales: number
  total_revenue: number
  average_rating?: number
  created_at: string
  updated_at: string
  seller?: Pick<User, 'id' | 'name' | 'avatar_url'>
  category?: Pick<Category, 'id' | 'name' | 'slug'>
  images?: ProductImage[]
  badges?: ProductBadge[]
}

export interface ProductImage {
  id: string
  product_id: string
  url: string
  alt_text?: string
  position: number
}


export interface AffiliateLink {
  id: string
  creator_id: string
  product_id: string
  code: string
  clicks: number
  conversions: number
  is_active: boolean
  created_at: string
  product?: Pick<Product, 'id' | 'name' | 'price' | 'commission_rate'>
  creator?: Pick<User, 'id' | 'name' | 'avatar_url'>
}

export interface ClickEvent {
  id: string
  affiliate_link_id: string
  ip_hash: string
  user_agent?: string
  referrer?: string
  converted: boolean
  created_at: string
}


export interface Order {
  id: string
  buyer_id: string
  seller_id: string
  affiliate_link_id?: string
  total_amount: number
  platform_fee: number
  seller_amount: number
  status: OrderStatus
  payment_status: PaymentStatus
  payment_ref?: string
  payment_method?: PaymentMethod
  shipping_name?: string
  shipping_address?: string
  shipping_city?: string
  shipping_country: string
  notes?: string
  created_at: string
  updated_at: string
  buyer?: Pick<User, 'id' | 'name' | 'email'>
  seller?: Pick<User, 'id' | 'name'>
  items?: OrderItem[]
}

export interface OrderItem {
  id: string
  order_id: string
  product_id: string
  quantity: number
  unit_price: number
  commission_rate: number
  commission_amount: number
  product?: Pick<Product, 'id' | 'name' | 'images'>
}


export interface Review {
  id: string
  product_id: string
  buyer_id: string
  order_id: string
  rating: number
  comment?: string
  is_verified: boolean
  created_at: string
  buyer?: Pick<User, 'id' | 'name' | 'avatar_url'>
}


export interface Commission {
  id: string
  creator_id: string
  order_id: string
  order_item_id: string
  amount: number
  status: CommissionStatus
  paid_at?: string
  payment_ref?: string
  created_at: string
  updated_at: string
  order?: Pick<Order, 'id' | 'total_amount' | 'created_at'>
}


export interface EscrowHold {
  id: string
  order_id: string
  total_amount: number
  platform_amount: number
  creator_amount: number
  seller_amount: number
  held_amount: number
  status: 'holding' | 'releasing' | 'released' | 'refunded'
  creator_release_at?: string
  seller_release_at?: string
  created_at: string
}

export interface Payout {
  id: string
  escrow_hold_id: string
  recipient_id: string
  order_id: string
  recipient_type: RecipientType
  amount: number
  currency: Currency
  status: PayoutStatus
  delay_minutes: number
  scheduled_at?: string
  triggered_by?: string
  recipient_payment_method?: PaymentMethod
  recipient_payment_number?: string
  psp_reference?: string
  executed_at?: string
  failure_reason?: string
  retry_count: number
  created_at: string
}

export interface PaymentTransaction {
  id: string
  order_id: string
  from_user_id?: string
  to_user_id?: string
  type: TransactionType
  amount: number
  currency: Currency
  status: TransactionStatus
  psp_reference?: string
  payment_method?: PaymentMethod
  description?: string
  processed_at?: string
  created_at: string
}


export interface ProductBadge {
  id: string
  product_id: string
  badge: BadgeType
  score: number
  rank_position?: number
  granted_at: string
  expires_at: string
}

export interface CreatorRanking {
  creator_id: string
  creator_name: string
  avatar_url?: string
  month: string
  total_orders: number
  total_commissions: number
  commission_count: number
  rank: number
}

export interface TopProduct {
  id: string
  name: string
  price: number
  commission_rate: number
  total_sales: number
  total_revenue: number
  average_rating?: number
  active_affiliates: number
  total_clicks: number
  conversion_rate: number
  sales_last_7d: number
  composite_score: number
  global_rank: number
  category_rank: number
  affiliation_rank: number
  sales_rank: number
  trending_rank: number
}


export interface ApiSuccess<T> {
  data: T
  message?: string
}

export interface ApiError {
  error: string
  message: string
}

export type ApiResponse<T> = ApiSuccess<T> | ApiError