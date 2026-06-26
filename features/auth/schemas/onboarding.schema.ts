import { z } from 'zod'

// ─── Types réseaux sociaux ────────────────────────────────────────
export const SOCIAL_PLATFORMS = [
  'instagram',
  'tiktok',
  'youtube',
  'facebook',
  'twitter',
  'whatsapp',
  'telegram',
  'linkedin',
  'other',
] as const

export type SocialPlatform = typeof SOCIAL_PLATFORMS[number]

// Schema d'un réseau social individuel
export const socialLinkSchema = z.object({
  platform: z.enum(SOCIAL_PLATFORMS, {
    error: 'Plateforme invalide',
  }),
  url: z.string().min(1, 'Lien ou numéro requis').max(300),
  // Pour WhatsApp et Telegram on stocke le numéro, pas une URL
  is_phone: z.boolean().default(false),
})

export type SocialLink = z.infer<typeof socialLinkSchema>

// ─── Creator onboarding ───────────────────────────────────────────
export const creatorOnboardingSchema = z.object({
  bio: z
    .string()
    .max(200, 'Maximum 200 caractères')
    .optional(),

  avatar_url: z
    .string()
    .url('URL invalide')
    .optional(),

  // Tableau de réseaux sociaux — tout optionnel
  social_links: z
    .array(socialLinkSchema)
    .max(8, 'Maximum 8 réseaux sociaux')
    .optional()
    .default([]),

  country: z.string().min(2).max(2).default('CM'),

  // Paiement optionnel
  payment_method: z.enum([
    'mtn_momo', 'orange_money', 'bank_transfer',
  ]).optional(),

  payment_number: z
    .string()
    .min(8, 'Numéro invalide')
    .max(20)
    .optional(),
})
.refine(
  data => {
    if (data.payment_method && !data.payment_number) return false
    if (data.payment_number && !data.payment_method) return false
    return true
  },
  {
    message: 'Renseignez le numéro correspondant à votre méthode de paiement',
    path: ['payment_number'],
  }
)

// ─── Seller onboarding ────────────────────────────────────────────
export const sellerOnboardingStep1Schema = z.object({
  shop_name: z
    .string()
    .min(2, 'Minimum 2 caractères')
    .max(100)
    .trim(),

  shop_description: z
    .string()
    .min(50, 'Minimum 50 caractères')
    .max(1000)
    .trim(),

  category_id: z.string().uuid('Catégorie invalide'),

  country: z.string().min(2).max(2).default('CM'),

  city: z.string().min(2).max(100).trim(),

  sells_physical: z.boolean().default(true),
  sells_digital:  z.boolean().default(false),

  // Réseaux sociaux optionnels pour la boutique aussi
  social_links: z
    .array(socialLinkSchema)
    .max(5, 'Maximum 5 réseaux sociaux')
    .optional()
    .default([]),
})
.refine(
  data => data.sells_physical || data.sells_digital,
  {
    message: 'Sélectionnez au moins un type de produit',
    path: ['sells_physical'],
  }
)

export const sellerOnboardingStep2Schema = z.object({
  id_holder_name: z
    .string()
    .min(2, 'Minimum 2 caractères')
    .max(100)
    .trim(),

  id_document_type: z.enum(['cni', 'passport', 'residence_permit']),

  id_document_url: z
    .string()
    .url('Veuillez uploader votre pièce d\'identité'),

  payment_method: z.enum([
    'mtn_momo', 'orange_money', 'bank_transfer',
  ]).optional(),

  payment_number: z
    .string()
    .min(8, 'Numéro invalide')
    .max(20)
    .optional(),
})
.refine(
  data => {
    if (data.payment_method && !data.payment_number) return false
    if (data.payment_number && !data.payment_method) return false
    return true
  },
  {
    message: 'Renseignez le numéro correspondant à votre méthode de paiement',
    path: ['payment_number'],
  }
)

// ─── Types inférés ────────────────────────────────────────────────
export type CreatorOnboardingInput     = z.infer<typeof creatorOnboardingSchema>
export type SellerOnboardingStep1Input = z.infer<typeof sellerOnboardingStep1Schema>
export type SellerOnboardingStep2Input = z.infer<typeof sellerOnboardingStep2Schema>