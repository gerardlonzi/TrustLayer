// features/products/schemas/product.schema.ts
import { z } from 'zod'

const baseProductSchema = z.object({
  name: z
    .string()
    .min(3, 'Product name must be at least 3 characters')
    .max(200, 'Product name cannot exceed 200 characters')
    .trim(),

  description: z
    .string()
    .min(10, 'Description must be at least 10 characters')
    .max(2000, 'Description cannot exceed 2000 characters')
    .trim(),

  price: z
    .number({ error: 'Price must be a number' })
    .positive('Price must be greater than 0')
    .max(10_000_000, 'Price cannot exceed 10,000,000 XAF'),

  commission_rate: z
    .number({ error: 'Commission rate must be a number' })
    .min(0.5, 'Minimum commission rate is 0.5%')
    .max(50, 'Maximum commission rate is 50%'),

  category_id: z
    .string()
    .uuid('Invalid category'),

  product_type: z.enum(['physical', 'digital']),

  images: z
    .array(z.string().url('Invalid image URL'))
    .min(1, 'At least one image is required')
    .max(8, 'Maximum 8 images allowed'),
})

const physicalProductSchema = baseProductSchema.extend({
  product_type: z.literal('physical'),

  stock_count: z
    .number()
    .int('Stock must be a whole number')
    .min(0, 'Stock cannot be negative')
    .default(0),

  weight_grams: z
    .number()
    .positive('Weight must be positive')
    .optional(),

  requires_shipping: z.boolean().default(true),
})

const digitalProductSchema = baseProductSchema.extend({
  product_type: z.literal('digital'),

  file_url: z
    .string()
    .url('Invalid file URL'),

  file_size_mb: z
    .number()
    .positive('File size must be positive')
    .optional(),

  preview_url: z
    .string()
    .url('Invalid preview URL')
    .optional(),
})

export const createProductSchema = z.discriminatedUnion('product_type', [
  physicalProductSchema,
  digitalProductSchema,
])

export const updateProductSchema = z.union([
  physicalProductSchema.partial().extend({ product_type: z.literal('physical') }),
  digitalProductSchema.partial().extend({ product_type: z.literal('digital') }),
])

export type CreateProductInput = z.infer<typeof createProductSchema>
export type UpdateProductInput = z.infer<typeof updateProductSchema>