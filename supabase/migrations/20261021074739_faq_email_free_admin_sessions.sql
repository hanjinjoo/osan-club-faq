
-- Project: achfgdunjdjztxsxneam ONLY. Migration requires 0 Auth users, 0 admins, 0 FAQs.
DO $guard$ BEGIN
 IF EXISTS (SELECT 1 FROM public.faq_admins) OR EXISTS (SELECT 1 FROM public.faq_items) OR EXISTS(SELECT 1 FROM public.faq_revisions)
 THEN RAISE EXCEPTION 'Migration refuses nonempty FAQ tables'; END IF;
END $guard$;
-- Old auth.users relationships are no longer used.
ALTER TABLE public.faq_admins DROP CONSTRAINT faq_admins_user_id_fkey;
ALTER TABLE public.faq_admins ALTER COLUMN user_id SET DEFAULT gen_random_uuid();
ALTER TABLE public.faq_admins ADD COLUMN password_hash text;
ALTER TABLE public.faq_admins ADD CONSTRAINT faq_admin_hash_check CHECK(password_hash IS NOT NULL AND length(password_hash) BETWEEN 50 AND 100);
ALTER TABLE public.faq_items DROP CONSTRAINT faq_items_created_by_fkey;
ALTER TABLE public.faq_items DROP CONSTRAINT faq_items_updated_by_fkey;
ALTER TABLE public.faq_revisions DROP CONSTRAINT faq_revisions_changed_by_fkey;
ALTER TABLE public.faq_items ADD CONSTRAINT faq_items_created_by_admin_fk FOREIGN KEY(created_by) REFERENCES public.faq_admins(user_id);
ALTER TABLE public.faq_items ADD CONSTRAINT faq_items_updated_by_admin_fk FOREIGN KEY(updated_by) REFERENCES public.faq_admins(user_id);
ALTER TABLE public.faq_revisions ADD CONSTRAINT faq_revisions_changed_by_admin_fk FOREIGN KEY(changed_by) REFERENCES public.faq_admins(user_id);
CREATE TABLE public.faq_sessions(
  token_hash text PRIMARY KEY CHECK(token_hash ~ '^[0-9a-f]{64}$'),
  admin_id uuid NOT NULL REFERENCES public.faq_admins(user_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz
);
CREATE INDEX faq_sessions_expiry ON public.faq_sessions(expires_at);
ALTER TABLE public.faq_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.faq_sessions FROM PUBLIC,anon,authenticated;
-- Retire old Auth-JWT based entrypoints. Keep public read-only functions.
REVOKE EXECUTE ON FUNCTION public.faq_admin_categories(),public.faq_admin_list(),public.faq_history(uuid),
 public.faq_save_draft(uuid,uuid,text,text,jsonb,int,boolean,int),public.faq_publish(uuid,int),
 public.faq_archive(uuid,int),public.faq_restore(uuid,uuid,int),
 public.faq_category_save(uuid,text,text,int,boolean),public.faq_my_role() FROM authenticated;
-- Only Edge Function service role may use the following RPCs.
CREATE FUNCTION public.faq_bootstrap_staff(p_staff text,p_password text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(191107,20261021);
 IF EXISTS(SELECT 1 FROM public.faq_admins) THEN RETURN false; END IF;
 IF p_staff !~ '^[0-9]{4,16}$' OR p_password IS NULL OR length(p_password)<12 OR octet_length(p_password)>72 THEN
   RAISE EXCEPTION 'Invalid initial credentials';
 END IF;
 INSERT INTO public.faq_admins(employee_no,password_hash,role,is_active)
 VALUES(p_staff,extensions.crypt(p_password,extensions.gen_salt('bf',12)),'owner',true);
 RETURN true;
END $$;

CREATE FUNCTION public.faq_signin_staff(p_staff text,p_password text,p_token_hash text,p_throttle_hash text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
DECLARE a public.faq_admins%rowtype; allowed boolean;
BEGIN
 IF p_staff !~ '^[0-9]{4,16}$' OR p_password IS NULL OR length(p_password)>256
  OR p_token_hash !~ '^[0-9a-f]{64}$' OR p_throttle_hash !~ '^[0-9a-f]{64}$' THEN RETURN false; END IF;
 PERFORM pg_advisory_xact_lock(hashtext(p_throttle_hash));
 SELECT public.faq_login_allow(p_throttle_hash) INTO allowed;
 IF NOT allowed THEN RETURN false; END IF;
 SELECT * INTO a FROM public.faq_admins WHERE employee_no=p_staff AND is_active=true;
 IF NOT FOUND OR a.password_hash IS NULL OR extensions.crypt(p_password,a.password_hash) IS DISTINCT FROM a.password_hash THEN
   PERFORM public.faq_login_failure(p_throttle_hash);
   RETURN false;
 END IF;
 DELETE FROM public.faq_login_attempts WHERE key_hash=p_throttle_hash;
 INSERT INTO public.faq_sessions(token_hash,admin_id,expires_at)
 VALUES(p_token_hash,a.user_id,now()+interval '8 hours');
 RETURN true;
END $$;

CREATE FUNCTION public.faq_admin_action(p_token_hash text,p_action text,p_data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions,pg_temp AS $$
DECLARE a_id uuid; i public.faq_items%rowtype; r public.faq_revisions%rowtype;
  fid uuid; rid uuid; cat_id uuid; v_version integer; v_sorted integer;
  v_question text; v_answer text; v_links jsonb; v_pin boolean; v_prev text; v_new text;
  link jsonb; output jsonb;
BEGIN
 IF p_token_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid session' USING errcode='28000'; END IF;
 SELECT a.user_id INTO a_id
 FROM public.faq_sessions s JOIN public.faq_admins a ON a.user_id=s.admin_id
 WHERE s.token_hash=p_token_hash AND s.revoked_at IS NULL AND s.expires_at>now() AND a.is_active=true;
 IF a_id IS NULL THEN RAISE EXCEPTION 'Session expired or unauthorized' USING errcode='28000'; END IF;
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' THEN RAISE EXCEPTION 'Invalid payload'; END IF;
 CASE p_action
 WHEN 'me' THEN
   RETURN jsonb_build_object('authenticated',true);
 WHEN 'logout' THEN
   UPDATE public.faq_sessions SET revoked_at=now() WHERE token_hash=p_token_hash;
   RETURN jsonb_build_object('ok',true);
 WHEN 'list' THEN
   SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.is_pinned DESC,v.sort_order,v.updated_at DESC),'[]'::jsonb) INTO output
   FROM (SELECT i.id,i.status,i.version,i.created_at,i.updated_at,i.public_updated_at,
     r.category_id,r.question,r.answer_md,r.related_links,r.is_pinned,r.sort_order
     FROM public.faq_items i JOIN public.faq_revisions r ON r.id=i.current_revision_id AND r.faq_id=i.id) v;
   RETURN output;
 WHEN 'categories' THEN
   SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.sort_order,c.name),'[]'::jsonb) INTO output
   FROM public.faq_categories c;
   RETURN output;
 WHEN 'history' THEN
   fid=(p_data->>'id')::uuid;
   SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.revision_number DESC),'[]'::jsonb) INTO output
   FROM (SELECT r.id,r.revision_number,r.question,r.answer_md,r.created_at
        FROM public.faq_revisions r WHERE r.faq_id=fid ORDER BY r.revision_number DESC LIMIT 250) v;
   RETURN output;
 WHEN 'save' THEN
   fid=nullif(p_data->>'id','')::uuid;
   cat_id=(p_data->>'category_id')::uuid;
   v_question=trim(p_data->>'question'); v_answer=trim(p_data->>'answer_md');
   v_pin=coalesce((p_data->>'is_pinned')::boolean,false);
   v_sorted=coalesce((p_data->>'sort_order')::integer,100);
   v_links=coalesce(p_data->'related_links','[]'::jsonb);
   IF v_question IS NULL OR length(v_question) NOT BETWEEN 1 AND 200 OR v_answer IS NULL OR length(v_answer) NOT BETWEEN 1 AND 10000
      OR v_sorted NOT BETWEEN 0 AND 99999 OR NOT EXISTS(SELECT 1 FROM public.faq_categories WHERE id=cat_id)
      OR jsonb_typeof(v_links)<>'array' OR jsonb_array_length(v_links)>10 THEN RAISE EXCEPTION 'Invalid FAQ content'; END IF;
   FOR link IN SELECT value FROM jsonb_array_elements(v_links) LOOP
      IF jsonb_typeof(link)<>'object' OR length(coalesce(link->>'label',''))>100 OR
         coalesce(link->>'url','') !~ '^https://[^[:space:]]{1,1992}$' THEN
         RAISE EXCEPTION 'Invalid related URL'; END IF;
   END LOOP;
   IF fid IS NULL THEN
     INSERT INTO public.faq_items(category_id,created_by,updated_by,is_pinned,sort_order)
     VALUES(cat_id,a_id,a_id,v_pin,v_sorted) RETURNING id INTO fid;
     v_version=0;
   ELSE
     SELECT * INTO i FROM public.faq_items WHERE id=fid FOR UPDATE;
     IF NOT FOUND THEN RAISE EXCEPTION 'FAQ not found'; END IF;
     IF i.version IS DISTINCT FROM (p_data->>'expected_version')::integer THEN RAISE EXCEPTION 'Conflict: reload FAQ' USING errcode='40001'; END IF;
     v_version=i.version;
   END IF;
   INSERT INTO public.faq_revisions(faq_id,revision_number,question,answer_md,related_links,category_id,is_pinned,sort_order,changed_by)
   VALUES(fid,v_version+1,v_question,v_answer,v_links,cat_id,v_pin,v_sorted,a_id) RETURNING id INTO rid;
   UPDATE public.faq_items SET current_revision_id=rid,version=v_version+1,updated_at=now(),updated_by=a_id WHERE id=fid;
   RETURN jsonb_build_object('id',fid);
 WHEN 'publish' THEN
   fid=(p_data->>'id')::uuid;
   SELECT * INTO i FROM public.faq_items WHERE id=fid FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'FAQ not found'; END IF;
   IF i.version IS DISTINCT FROM (p_data->>'expected_version')::integer THEN RAISE EXCEPTION 'Conflict: reload FAQ' USING errcode='40001'; END IF;
   SELECT * INTO r FROM public.faq_revisions WHERE id=i.current_revision_id AND faq_id=fid;
   IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.faq_categories WHERE id=r.category_id AND is_visible) THEN
     RAISE EXCEPTION 'Category is not public'; END IF;
   UPDATE public.faq_items SET category_id=r.category_id,is_pinned=r.is_pinned,sort_order=r.sort_order,
     published_revision_id=r.id,status='published',published_at=coalesce(published_at,now()),
     public_updated_at=now(),version=version+1,updated_at=now(),updated_by=a_id WHERE id=fid;
   RETURN jsonb_build_object('ok',true);
 WHEN 'archive' THEN
   fid=(p_data->>'id')::uuid;
   SELECT * INTO i FROM public.faq_items WHERE id=fid FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'FAQ not found'; END IF;
   IF i.version IS DISTINCT FROM (p_data->>'expected_version')::integer THEN RAISE EXCEPTION 'Conflict: reload FAQ' USING errcode='40001'; END IF;
   UPDATE public.faq_items SET status='archived',version=version+1,updated_by=a_id,updated_at=now() WHERE id=fid;
   RETURN jsonb_build_object('ok',true);
 WHEN 'restore' THEN
   fid=(p_data->>'id')::uuid;
   rid=(p_data->>'revision_id')::uuid;
   SELECT * INTO i FROM public.faq_items WHERE id=fid FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'FAQ not found'; END IF;
   IF i.version IS DISTINCT FROM (p_data->>'expected_version')::integer THEN RAISE EXCEPTION 'Conflict: reload FAQ' USING errcode='40001'; END IF;
   SELECT * INTO r FROM public.faq_revisions WHERE faq_id=fid AND id=rid;
   IF NOT FOUND THEN RAISE EXCEPTION 'Revision not found'; END IF;
   INSERT INTO public.faq_revisions(faq_id,revision_number,question,answer_md,related_links,category_id,is_pinned,sort_order,changed_by,change_note)
   VALUES(fid,i.version+1,r.question,r.answer_md,r.related_links,r.category_id,r.is_pinned,r.sort_order,a_id,'restored revision '||r.revision_number)
   RETURNING id INTO rid;
   UPDATE public.faq_items SET current_revision_id=rid,updated_by=a_id,updated_at=now(),version=version+1 WHERE id=fid;
   RETURN jsonb_build_object('ok',true);
 WHEN 'category_save' THEN
   fid=nullif(p_data->>'id','')::uuid;v_question=trim(p_data->>'name');
   v_answer=trim(p_data->>'slug');v_sorted=(p_data->>'sort_order')::integer;
   v_pin=coalesce((p_data->>'is_visible')::boolean,true);
   IF v_answer !~ '^[a-z0-9-]{2,50}$' OR length(v_question) NOT BETWEEN 1 AND 70 OR v_sorted NOT BETWEEN 0 AND 99999 THEN
     RAISE EXCEPTION 'Invalid category';END IF;
   IF fid IS NULL THEN
     INSERT INTO public.faq_categories(slug,name,sort_order,is_visible)
     VALUES(v_answer,v_question,v_sorted,v_pin) RETURNING id INTO fid;
   ELSE
     UPDATE public.faq_categories SET slug=v_answer,name=v_question,sort_order=v_sorted,is_visible=v_pin,updated_at=now()
     WHERE id=fid RETURNING id INTO fid;
     IF fid IS NULL THEN RAISE EXCEPTION 'Category not found'; END IF;
   END IF;
   RETURN jsonb_build_object('id',fid);
 WHEN 'change_password' THEN
   v_prev=p_data->>'old_password';v_new=p_data->>'new_password';
   IF v_new IS NULL OR length(v_new)<12 OR octet_length(v_new)>72 THEN RAISE EXCEPTION 'New password must be 12+ characters, max 72 bytes'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.faq_admins
      WHERE user_id=a_id AND password_hash=extensions.crypt(v_prev,password_hash)) THEN
      RAISE EXCEPTION 'Invalid current password' USING errcode='28000'; END IF;
   UPDATE public.faq_admins SET password_hash=extensions.crypt(v_new,extensions.gen_salt('bf',12)),updated_at=now() WHERE user_id=a_id;
   UPDATE public.faq_sessions SET revoked_at=now() WHERE admin_id=a_id AND token_hash<>p_token_hash AND revoked_at IS NULL;
   RETURN jsonb_build_object('ok',true);
 ELSE RAISE EXCEPTION 'Unsupported action'; END CASE;
END $$;

REVOKE ALL ON FUNCTION public.faq_bootstrap_staff(text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.faq_signin_staff(text,text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.faq_admin_action(text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.faq_bootstrap_staff(text,text),
 public.faq_signin_staff(text,text,text,text),public.faq_admin_action(text,text,jsonb) TO service_role;
