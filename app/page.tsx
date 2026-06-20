'use client'


import Image from "next/image";
import { useState,useEffect,useMemo } from "react";




export default function Home() {

const [currentValue, setCurrent] = useState<number>(0)
const [currentMessage, setCurrentMessage] = useState<string>("")

  return (
     <div className="mt-20 mx-36 text-blue-300 flex gap-10">
      <button onClick={()=>setCurrent(currentValue + 1)}>+1</button>
      <button onClick={()=>setCurrent(currentValue + 3)}>+3</button>
      <p>le score est de {currentValue} </p>
      <p>you are typing {currentMessage}</p>

     </div>
  )
}
