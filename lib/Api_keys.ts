export const valid_api_key = [
    "tl_test_123456",
    "tl_test_asdfg"
]

export function IsvalidApi_key(Api_key:string | null):boolean{
    const Gotton = valid_api_key.find(el => el===Api_key)
    if(!Api_key) return false
    
    return valid_api_key.includes(Api_key)
}  
