import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read=path=>readFileSync(new URL('../'+path,import.meta.url),'utf8');
test('FAQ admin SQL record variables are distinct from list/history table aliases',()=>{
 const sql=read('supabase/migrations/20261021_faq_fix_admin_action_aliases.sql');
 assert.match(sql,/v_item_row public\.faq_items%rowtype/);
 assert.match(sql,/v_revision_row public\.faq_revisions%rowtype/);
 assert.ok(!sql.includes(' i public.faq_items%rowtype'));
 assert.ok(!sql.includes(' r public.faq_revisions%rowtype'));
 assert.match(sql,/SELECT i\.id,i\.status,i\.version/);
 assert.match(sql,/r\.id=i\.current_revision_id/);
 assert.match(sql,/SELECT r\.id,r\.revision_number/);
});
test('Login and subsequent admin data loading are reported separately',()=>{
 const html=read('admin/index.html');
 assert.match(html,/로그인은 성공했습니다\. 관리자 데이터 조회 오류/);
 assert.match(html,/const loaded=await enter\(\);if\(loaded\)alertText/);
 assert.match(html,/새로고침 버튼으로 다시 시도해 주세요/);
});
