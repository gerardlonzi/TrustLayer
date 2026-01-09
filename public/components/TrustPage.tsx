'use client'
import { useState } from "react"

export default function TrustPage(){
    const [score ,setScore]= useState(50)
    return(
        <div>
            {score} <br />
            Trust core {score>=70 ?"HIGHT SCORE" :"LOW SCORE"}
            <button className="bg-red-300" onClick={()=>setScore(score+10)}>increase score</button>
        </div>
    )
}