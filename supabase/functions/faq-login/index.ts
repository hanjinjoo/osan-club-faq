import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.79.0';
const projectUrl=Deno.env.get('SUPABASE_URL')??'';
const publishableKey=Deno.env.get('SUPABASE_ANON_KEY')??'';
const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'';
const pepper=Deno.env.get('FAQ_LOGIN_PEPPER')??'';
const originAllowed='https://hanjinjoo.github.io';
const cors={'Access-Control-Allow-Origin':originAllowed,'Access-Control-Allow-Headers':'content-type,apikey,authorization','Access-Control-Allow-Methods':'POST,OPTIONS','Vary':'Origin'};
function response(data:Record<string,unknown>,status=200){return new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json;charset=utf-8','Cache-Control':'no-store'}})}
async function sha256(s:string){const bytes=new TextEncoder().encode(s);const buf=await crypto.subtle.digest('SHA-256',bytes);return Array.from(new Uint8Array(buf),b=>b.toString(16).padStart(2,'0')).join('')}
Deno.serve(async req=>{
 if(req.headers.get('origin')!==originAllowed)return response({error:'허용되지 않은 사이트입니다.'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return response({error:'지원하지 않는 요청입니다.'},405);
 if(!projectUrl||!publishableKey||!serviceKey||pepper.length<32)return response({error:'FAQ 인증 서버의 초기 설정이 완료되지 않았습니다.'},503);
 let body:Record<string,unknown>;
 try{if(Number(req.headers.get('content-length')||0)>4096)return response({error:'요청이 너무 큽니다.'},413);body=await req.json()}catch{return response({error:'요청 형식이 올바르지 않습니다.'},400)}
 const staff=String(body.employee_no??'').trim();const password=body.password;
 if(!/^[0-9]{4,16}$/.test(staff)||typeof password!=='string'||password.length<1||password.length>256)return response({error:'사번 또는 비밀번호를 확인해 주세요.'},400);
 const keyHash=await sha256('faq-staff-login:'+pepper+':'+staff);
 const admin=createClient(projectUrl,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:allowed,error:limitError}=await admin.rpc('faq_login_allow',{p_key_hash:keyHash});
 if(limitError)return response({error:'인증을 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.'},503);
 if(!allowed)return response({error:'로그인 시도가 많습니다. 15분 후 다시 시도해 주세요.'},429);
 const {data:staffRow,error:staffError}=await admin.from('faq_admins').select('user_id,is_active').eq('employee_no',staff).maybeSingle();
 if(staffError)return response({error:'로그인 확인 중 오류가 발생했습니다.'},503);
 const fail=async()=>{await admin.rpc('faq_login_failure',{p_key_hash:keyHash});return response({error:'사번 또는 비밀번호가 올바르지 않습니다.'},401)};
 if(!staffRow?.is_active)return fail();
 const {data:profile,error:profileError}=await admin.auth.admin.getUserById(staffRow.user_id);
 if(profileError||!profile.user?.email)return response({error:'관리자 계정 설정을 확인해 주세요.'},503);
 const auth=createClient(projectUrl,publishableKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:login,error:loginError}=await auth.auth.signInWithPassword({email:profile.user.email,password});
 if(loginError||!login.session||login.user?.id!==staffRow.user_id)return fail();
 await admin.rpc('faq_login_success',{p_key_hash:keyHash});
 return response({access_token:login.session.access_token,refresh_token:login.session.refresh_token,expires_in:login.session.expires_in});
});
