function haversine(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371
  const dLat = ((lat2 - lat1) * Math.PI) / 180
  const dLon = ((lon2 - lon1) * Math.PI) / 180

  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) *
      Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLon / 2) ** 2

  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

export function geoDistancePenalty(
  ipLat?: number,
  ipLon?: number,
  userLat?: number,
  userLon?: number
): { penalty: number; reason?: string } {
  if (
    ipLat == null ||
    ipLon == null ||
    userLat == null ||
    userLon == null
  ) {
    return { penalty: 0 }
  }

  const distance = haversine(ipLat, ipLon, userLat, userLon)

  if (distance < 50) return { penalty: 0 }
  if (distance < 300) return { penalty: 5, reason: "GEO_NEAR_MISMATCH" }
  if (distance < 1000) return { penalty: 15, reason: "GEO_REGIONAL_MISMATCH" }

  return { penalty: 30, reason: "GEO_LONG_DISTANCE_MISMATCH" }
}
