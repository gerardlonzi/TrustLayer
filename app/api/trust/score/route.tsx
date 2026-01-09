import { NextResponse } from "next/server";
import { CalculateTrustcore } from "@/lib/trust/score";
import { IsvalidApi_key } from "@/lib/Api_keys";
export async function GET(request:Request){

    const Api_key = request.headers.get("authorization")?.replace("Bearer","")
    if(!IsvalidApi_key(Api_key)){
        return NextResponse.json({status : 404},{error :"Unauthorized"})
    }
    const {searchParams} = new URL(request.url)
    const emailValid = searchParams.get("emailValid")=="true"
    const result = CalculateTrustcore(emailValid)

    return NextResponse.json({
        success:true,
        data : result
    })
}   