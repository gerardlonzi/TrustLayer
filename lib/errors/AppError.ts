
export class AppError extends Error {
    constructor(
      public readonly code: string,
      message: string,
      public readonly statusCode: number = 400
    ) {
      super(message)
      this.name = 'AppError'
    }
  }
  
  export class UnauthorizedError extends AppError {
    constructor(message = 'Not authenticated') {
      super('UNAUTHORIZED', message, 401)
    }
  }
  
  export class ForbiddenError extends AppError {
    constructor(message = 'Access denied') {
      super('FORBIDDEN', message, 403)
    }
  }
  
  export class NotFoundError extends AppError {
    constructor(resource: string) {
      super('NOT_FOUND', `${resource} not found`, 404)
    }
  }
  
  export class ValidationError extends AppError {
    constructor(message: string) {
      super('VALIDATION_ERROR', message, 422)
    }
  }
  
  export class ConflictError extends AppError {
    constructor(message: string) {
      super('CONFLICT', message, 409)
    }
  }
  
  export function toResponse(error: unknown): Response {
    if (error instanceof AppError) {
      return Response.json(
        {
          error: error.code,
          message: error.message,
        },
        { status: error.statusCode }
      )
    }
  
    console.error('Unexpected error:', error)
    return Response.json(
      {
        error: 'INTERNAL_ERROR',
        message: 'An unexpected error occurred',
      },
      { status: 500 }
    )
  }