'use client'


import Image from "next/image";
import TrustPage from "@/public/components/TrustPage";
import { useState,useEffect } from "react";
import { CalculateTrustcore } from "@/lib/trust/score";

export default function Home() {
  const [emailValid,setValidEmail] = useState(false)
  const [result, setResult] = useState<any>(null)

useEffect(()=>{
  fetch(`/api/trust/score?emailValid=${emailValid}`).
  then(res=>res.json())
  .then(data=>setResult(data.data))

},[emailValid])
if(!result) return <p>...loading</p>



  return (
    <div className="dark:bg-black">
      <h1>Trust score {result.score}</h1>
      <h1>Risk {result.risk}</h1>
      <button onClick={()=>setValidEmail(!emailValid)}>Toogle email</button>
      <p>Digital strust infrastrure</p>
    </div>
  );
}
