import validator from 'validator'
import dns from 'dns/promises'

const DISPOSABLE_EMAILS = [
    "tempmail.com",
  "10minutemail.com",
  "mailinator.com",
  "yopmail.com",
  "temp-mail.org",
  "guerrillamail.com",
  "maildrop.cc",
  "nada.email",
  "trashmail.com",
  "20minutemail.com",
  "mailnesia.com",
  "dispostable.com",
  "emailondeck.com",
  "bccto.me",
  "mohmal.com"
]

export async function Validator_email(email:string){
    if(!validator.isEmail(email)){
        return {valid :false , reason :"INVALID_FORMAT"}
    }
    const domain = email.split("@")[1]

    if(DISPOSABLE_EMAILS.includes(domain)){
         return {valid:false, reason: "DISPOSABLE_EMAIL"}
    }

    try{
        const mx = await dns.resolveMx(domain)
        if(!mx || mx.length === 0){
            return {valid:false, reason:"NO_DX"}
        }
    }
    catch{
        return {valid:false,reason:"DOMAIN_NOT_FOUND"}
    }
    return {valid:false}

}