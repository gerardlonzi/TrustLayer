export function timezonePenalty(
    ipTz?: string,
    userTz?: string
  ): { penalty: number; reason?: string } {
    if (!ipTz || !userTz) {
      return { penalty: 0 }
    }
  
    if (ipTz === userTz) {
      return { penalty: 0 }
    }
  
    return { penalty: 20, reason: "TIMEZONE_MISMATCH" }
  }
  