import { TrustResult } from "./types";

export function CalculateTrustcore(emailValid:boolean):TrustResult{
    let score = 0
    if(emailValid){
        score +=60
    }
    let risk:TrustResult['risk']
    if(score>=70) risk='LOW'
    else if(score >40) risk='MEDUIM'
    else risk ='HIGH'

    return {score, risk}
}
    