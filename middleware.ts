
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { updateSession } from '@/lib/supabase/middleware'

const ROUTE_RULES = {

  authOnly: [
    '/auth/login',
    '/auth/register',
  ],

  protected: [
    '/account',
    '/checkout',
  ],

  roleRoutes: {
    seller:  ['/dashboard/seller'],
    creator: ['/dashboard/creator'],
    admin:   ['/dashboard/admin'],
  } as const,

  apiRoleRoutes: {
    seller: ['/api/products/create'],
    admin:  ['/api/admin'],
  } as const,
}


export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  const { supabaseResponse, user } = await updateSession(request)

  const role = user?.user_metadata?.['role'] as string | undefined

  if (ROUTE_RULES.authOnly.some(r => pathname.startsWith(r))) {
    if (user) {
      return NextResponse.redirect(
        new URL(getDashboardUrl(role), request.url)
      )
    }
    return supabaseResponse
  }

  if (ROUTE_RULES.protected.some(r => pathname.startsWith(r))) {
    if (!user) return redirectToLogin(request)
    return supabaseResponse
  }

  for (const [requiredRole, routes] of Object.entries(ROUTE_RULES.roleRoutes)) {
    if ((routes as readonly string[]).some(r => pathname.startsWith(r))) {
      if (!user) return redirectToLogin(request)

      if (role !== requiredRole) {
        return NextResponse.json(
          {
            error: 'FORBIDDEN',
            message: 'You do not have access to this page',
          },
          { status: 403 }
        )
      }
    }
  }

  for (const [requiredRole, routes] of Object.entries(ROUTE_RULES.apiRoleRoutes)) {
    if ((routes as readonly string[]).some(r => pathname.startsWith(r))) {
      if (!user) {
        return NextResponse.json(
          {
            error: 'UNAUTHORIZED',
            message: 'Authentication required',
          },
          { status: 401 }
        )
      }
      if (role !== requiredRole) {
        return NextResponse.json(
          {
            error: 'FORBIDDEN',
            message: 'Insufficient permissions',
          },
          { status: 403 }
        )
      }
    }
  }

  return supabaseResponse
}


function redirectToLogin(request: NextRequest): NextResponse {
  const loginUrl = new URL('/auth/login', request.url)

  loginUrl.searchParams.set('callbackUrl', request.nextUrl.pathname)

  return NextResponse.redirect(loginUrl)
}

function getDashboardUrl(role?: string): string {
  const dashboards: Record<string, string> = {
    seller:  '/dashboard/seller',
    creator: '/dashboard/creator',
    admin:   '/dashboard/admin',
  }
  return dashboards[role ?? ''] ?? '/account'
}


export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|css|js)$).*)',
  ],
}