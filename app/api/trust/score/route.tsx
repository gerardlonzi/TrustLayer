import { NextResponse } from "next/server"
import { evaluateTrust } from "@/lib/trust/engine"

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url)

  const userSignals = {
    ip: searchParams.get("ip")!,
    timezone: searchParams.get("timezone") || undefined,
    latitude: Number(searchParams.get("lat")),
    longitude: Number(searchParams.get("lon")),
    ipInfo: {
      timezone: "Africa/Douala",
      latitude: 3.848,
      longitude: 11.502,
      vpn: false,
      proxy: false,
      tor: false,
      hosting: false
    }
  }

  const result = evaluateTrust(userSignals)

  return NextResponse.json(result)
}
