import { NextResponse } from "next/server";
import { CalculateTrustcore } from "@/lib/trust/score";
import { IsvalidApi_key } from "@/lib/Api_keys";
import { Validator_email } from "@/lib/trust/email";

export async function GET(request:Request){

    const Api_key = request.headers.get("Authorization")?.replace("Bearer ","") 
    if(!IsvalidApi_key(Api_key)){
        return NextResponse.json({error :"Unauthorized"},{status : 401})
    }
    const {searchParams} = new URL(request.url)
    const email = searchParams.get("emailValid")
    if(!email){
        return NextResponse.json({error : "email is required"},{status:400})
    }

    const emailCheck = await Validator_email(email)
    const result = CalculateTrustcore(emailCheck.valid)

    return NextResponse.json({
        success:true,
        data : result,
        email: emailCheck
    })
}   