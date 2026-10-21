import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.79.0';
const ORIGIN='https://hanjinjoo.github.io';
const headers={
 'Access-Control-Allow-Origin':ORIGIN,'Access-Control-Allow-Headers':'content-type,authorization,apikey',
 'Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin','Cache-Control':'no-store'
};
const json=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{
 status,headers:{...headers,'Content-Type':'application/json; charset=utf-8'}});
const fail=(message:string,status=400)=>json({error:message},status);
const encode=(bytes:Uint8Array)=>Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
async function digest(x:string){return encode(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(x))))}
function equals(a:string,b:string){const A=new TextEncoder().encode(a),B=new TextEncoder().encode(b);let diff=A.length^B.length;for(let i=0;i<Math.max(A.length,B.length);i++)diff|=(A[i]||0)^(B[i]||0);return diff===0}
function randomToken(){const a=new Uint8Array(32);crypto.getRandomValues(a);return btoa(String.fromCharCode(...a)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')}
const url=Deno.env.get('SUPABASE_URL')||'';
const role=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'';
const pepper=Deno.env.get('FAQ_LOGIN_PEPPER')||'';
const bootstrap=Deno.env.get('FAQ_BOOTSTRAP_SECRET')||'';
Deno.serve(async(req:Request)=>{
 if(req.headers.get('origin')!==ORIGIN)return fail('허용되지 않은 출처입니다.',403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return fail('지원하지 않는 요청입니다.',405);
 if(!url||!role)return fail('서버 연결 구성이 완료되지 않았습니다.',503);
 const svc=createClient(url,role,{auth:{persistSession:false,autoRefreshToken:false}});
 let raw:string,body:Record<string,unknown>;
 try{raw=await req.text();if(raw.length>25000)return fail('요청이 너무 큽니다.',413);
 body=JSON.parse(raw);if(!body||typeof body!=='object'||Array.isArray(body))throw Error('invalid')}
 catch{return fail('요청 형식이 잘못되었습니다.',400)}
 const action=String(body.action||'');
 if(action==='status'){
  const {count,error}=await svc.from('faq_admins').select('user_id',{head:true,count:'exact'});
  if(error)return fail('설정 상태를 확인할 수 없습니다.',503);
  return json({setup_required:count===0});
 }
 if(pepper.length<32)return fail('관리자 인증 서버 비밀값을 설정해야 합니다.',503);
 if(action==='bootstrap'){
  if(bootstrap.length<32)return fail('최초 등록용 비밀값을 설정해야 합니다.',503);
  const secret=body.setup_secret, staff=body.employee_no, pass=body.password;
  if(typeof secret!=='string'||typeof staff!=='string'||typeof pass!=='string'||!(/^[0-9]{4,16}$/.test(staff))
   ||pass.length<12||new TextEncoder().encode(pass).length>72||secret.length>512)return fail('등록 정보가 올바르지 않습니다.');
  const equal=equals(await digest(secret),await digest(bootstrap));
  if(!equal)return fail('등록 코드가 올바르지 않습니다.',403);
  const {data,error}=await svc.rpc('faq_bootstrap_staff',{p_staff:staff,p_password:pass});
  if(error)return fail('관리자 최초 등록에 실패했습니다.',400);
  if(!data)return fail('관리자 등록이 이미 완료되었습니다.',409);
  return json({ok:true});
 }
 if(action==='login'){
  const staff=body.employee_no,pass=body.password;
  if(typeof staff!=='string'||typeof pass!=='string'||!(/^[0-9]{4,16}$/.test(staff))||pass.length>256)return fail('사번 또는 비밀번호가 올바르지 않습니다.',401);
  const token=randomToken();
  const tokenHash=await digest('faq-session:'+pepper+':'+token);
  const throttle=await digest('faq-employee:'+pepper+':'+staff);
  const {data,error}=await svc.rpc('faq_signin_staff',{p_staff:staff,p_password:pass,p_token_hash:tokenHash,p_throttle_hash:throttle});
  if(error)return fail('로그인 서버 오류입니다.',503);
  if(!data)return fail('사번 또는 비밀번호가 올바르지 않습니다. 반복 실패 시 15분간 제한됩니다.',401);
  return json({token,expires_in:28800});
 }
 const allowed=['me','logout','list','categories','history','save','publish','archive','restore','category_save','change_password'];
 if(!allowed.includes(action))return fail('지원하지 않는 기능입니다.',400);
 const bearer=req.headers.get('authorization')||'';
 if(!/^Bearer [a-zA-Z0-9_-]{40,80}$/.test(bearer))return fail('로그인이 필요합니다.',401);
 const token=bearer.slice(7);
 const tokenHash=await digest('faq-session:'+pepper+':'+token);
 const data=body.data;
 if(data!==undefined&&(!data||typeof data!=='object'||Array.isArray(data)))return fail('잘못된 입력입니다.');
 const {data:result,error}=await svc.rpc('faq_admin_action',{p_token_hash:tokenHash,p_action:action,p_data:data??{}});
 if(error){
  if(error.code==='28000')return fail('로그인이 만료되었거나 인증되지 않았습니다.',401);
  if(error.code==='40001')return fail('다른 변경이 먼저 저장되었습니다. 새로고침 후 다시 시도하세요.',409);
  // Never return DB details or SQL query to browser.
  if(action==='save')return fail('질문 저장을 처리하지 못했습니다. 질문 내용과 HTTPS 링크를 확인한 뒤 다시 시도해 주세요.',400);
  if(action==='category_save')return fail('카테고리 입력값을 확인하거나 다시 시도해 주세요.',400);
  if(action==='change_password')return fail('현재 비밀번호나 새 비밀번호 조건을 확인해 주세요.',400);
  return fail('요청 처리에 실패했습니다.',400);
 }
 return json({data:result});
});