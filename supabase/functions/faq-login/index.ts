const ORIGIN='https://hanjinjoo.github.io';
Deno.serve(req=>{
 const h={'Access-Control-Allow-Origin':ORIGIN,'Access-Control-Allow-Headers':'content-type,authorization,apikey',
 'Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin','Cache-Control':'no-store','Content-Type':'application/json'};
 if(req.headers.get('origin')!==ORIGIN)return new Response(JSON.stringify({error:'Forbidden'}),{status:403,headers:h});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:h});
 return new Response(JSON.stringify({error:'이메일 기반 이전 로그인 API는 폐기되었습니다. 최신 관리자 페이지를 이용해 주세요.'}),{status:410,headers:h});
});