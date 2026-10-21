import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const get=name=>readFileSync(new URL('../'+name,import.meta.url),'utf8');

test('FAQ save validates HTTPS related URL without invalid PostgreSQL large repetition quantifier',()=>{
 const sql=get('supabase/migrations/20261021_faq_fix_url_regex.sql');
 assert.ok(sql.includes("length(coalesce(link->>'url',''))>2000"));
 assert.ok(sql.includes("coalesce(link->>'url','') !~ '^https://[^[:space:]]+$'"));
 assert.ok(!sql.includes('{1,1992}'));
 assert.match(sql,/CREATE OR REPLACE FUNCTION public\.faq_admin_action/);
});
test('Saving and password changing have distinct user-facing server errors',()=>{
 const js=get('supabase/functions/faq-admin/index.ts');
 assert.ok(js.includes("if(action==='save')return fail("));
 assert.ok(js.includes("if(action==='change_password')return fail("));
 assert.ok(!js.includes('입력값 또는 기존 비밀번호를 확인해 주세요.'));
});
test('Publishing displays success in the admin UI and leaves student link new-tab',()=>{
 const html=get('admin/index.html');
 assert.ok(html.includes('게시 완료! 학생용 화면에서 확인할 수 있습니다.'));
 assert.ok(html.includes('target="_blank" rel="noopener noreferrer"'));
});
