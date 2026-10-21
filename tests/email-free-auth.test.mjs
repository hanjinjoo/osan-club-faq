import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const file=x=>readFileSync(new URL('../'+x,import.meta.url),'utf8');
test('Admin uses staff+password and an opaque 8 hour session, not email/SignInWithPassword',()=>{
 const html=file('admin/index.html'),server=file('supabase/functions/faq-admin/index.ts');
 assert.ok(html.includes('setup-form')&&html.includes('setup-staff')&&html.includes('setup-secret'));
 assert.ok(html.includes('faq-admin')&&html.includes("sessionStorage.getItem('faq_admin_token')"));
 assert.ok(!html.includes('sb.auth')&&!html.includes('signInWithPassword')&&!html.includes('getClient()'));
 assert.ok(server.includes("FAQ_LOGIN_PEPPER")&&server.includes("FAQ_BOOTSTRAP_SECRET"));
 assert.ok(server.includes("expires_in:28800")&&server.includes('crypto.getRandomValues'));
 assert.ok(server.includes("'Cache-Control':'no-store'"));
});
test('All admin writes require a server session and are never exposed through anon RPC',()=>{
 const sql=file('supabase/migrations/20261021074739_faq_email_free_admin_sessions.sql');
 const src=file('supabase/functions/faq-admin/index.ts');
 assert.match(sql,/CREATE FUNCTION public\.faq_admin_action/);
 assert.match(sql,/REVOKE ALL ON FUNCTION public\.faq_admin_action\(text,text,jsonb\) FROM PUBLIC,anon,authenticated/);
 assert.match(sql,/GRANT EXECUTE ON FUNCTION public\.faq_bootstrap_staff/);
 assert.match(sql,/expires_at>now\(\)/);
 assert.match(src,/faq_admin_action/);
 assert.ok(!src.includes('SUPABASE_SERVICE_ROLE_KEY:'));
});
test('Legacy email-backed login is retired',()=>{
 const old=file('supabase/functions/faq-login/index.ts');
 assert.match(old,/status:410/);
 assert.ok(!old.includes('signInWithPassword'));
});
test('Public FAQ and admin UI links remain on separate origin routes',()=>{
 const student=file('index.html'),admin=file('admin/index.html');
 assert.ok(student.includes('faq_public_list'));
 assert.ok(student.includes('target="_blank" rel="noopener noreferrer"'));
 assert.ok(admin.includes('비공개')&&admin.includes('수정 이력')&&admin.includes('복원'));
});
