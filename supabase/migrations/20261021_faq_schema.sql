-- FAQ-only initialization reconstructed from the deployed FAQ database; NEVER apply to the monitoring project.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE public.faq_categories(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),slug text NOT NULL UNIQUE CHECK(slug ~ '^[a-z0-9-]{2,50}$'),
 name text NOT NULL CHECK(length(name) BETWEEN 1 AND 70),sort_order int NOT NULL DEFAULT 100,
 is_visible boolean NOT NULL DEFAULT true,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.faq_admins(
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,employee_no text NOT NULL UNIQUE CHECK(employee_no ~ '^[0-9]{4,16}$'),
 role text NOT NULL DEFAULT 'owner' CHECK(role='owner'),singleton boolean NOT NULL DEFAULT true UNIQUE CHECK(singleton=true),
 is_active boolean NOT NULL DEFAULT true,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.faq_items(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),category_id uuid NOT NULL REFERENCES public.faq_categories(id),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','archived')),is_pinned boolean NOT NULL DEFAULT false,
 sort_order int NOT NULL DEFAULT 100,current_revision_id uuid,published_revision_id uuid,version int NOT NULL DEFAULT 0 CHECK(version>=0),
 created_by uuid NOT NULL REFERENCES auth.users(id),updated_by uuid NOT NULL REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),published_at timestamptz,public_updated_at timestamptz
);
CREATE TABLE public.faq_revisions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),faq_id uuid NOT NULL REFERENCES public.faq_items(id) ON DELETE RESTRICT,
 revision_number int NOT NULL CHECK(revision_number>0),question text NOT NULL CHECK(length(question) BETWEEN 1 AND 200),
 answer_md text NOT NULL CHECK(length(answer_md) BETWEEN 1 AND 10000),
 related_links jsonb NOT NULL DEFAULT '[]'::jsonb CHECK(jsonb_typeof(related_links)='array'),
 category_id uuid NOT NULL REFERENCES public.faq_categories(id),is_pinned boolean NOT NULL DEFAULT false,sort_order int NOT NULL DEFAULT 100,
 changed_by uuid NOT NULL REFERENCES auth.users(id),change_note text,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(faq_id,revision_number)
);
ALTER TABLE public.faq_items ADD CONSTRAINT faq_current_revision_fk FOREIGN KEY(current_revision_id) REFERENCES public.faq_revisions(id) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE public.faq_items ADD CONSTRAINT faq_published_revision_fk FOREIGN KEY(published_revision_id) REFERENCES public.faq_revisions(id) DEFERRABLE INITIALLY DEFERRED;
CREATE INDEX faq_items_public_sort_idx ON public.faq_items(status,is_pinned DESC,sort_order);
CREATE INDEX faq_revisions_history_idx ON public.faq_revisions(faq_id,revision_number DESC);
CREATE TABLE public.faq_login_attempts(
 key_hash text PRIMARY KEY CHECK(key_hash ~ '^[0-9a-f]{64}$'),failure_count integer NOT NULL DEFAULT 0,
 window_started_at timestamptz NOT NULL DEFAULT now(),blocked_until timestamptz
);
ALTER TABLE public.faq_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faq_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faq_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faq_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.faq_login_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.faq_categories,public.faq_admins,public.faq_items,public.faq_revisions,public.faq_login_attempts FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.faq_my_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 SELECT role FROM public.faq_admins WHERE user_id=(SELECT auth.uid()) AND is_active=true LIMIT 1
$function$


;

CREATE OR REPLACE FUNCTION public.faq_is_editor()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 SELECT (SELECT auth.uid()) IS NOT NULL AND EXISTS(SELECT 1 FROM public.faq_admins a WHERE a.user_id=(SELECT auth.uid()) AND a.is_active=true AND a.role='owner')
$function$


;

CREATE OR REPLACE FUNCTION public.faq_is_owner()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 SELECT public.faq_is_editor() AND public.faq_my_role()='owner'
$function$


;

CREATE OR REPLACE FUNCTION public.faq_public_categories()
 RETURNS TABLE(id uuid, name text, sort_order integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 SELECT id,name,sort_order FROM public.faq_categories WHERE is_visible=true ORDER BY sort_order,name
$function$


;

CREATE OR REPLACE FUNCTION public.faq_public_list()
 RETURNS TABLE(id uuid, category_id uuid, question text, answer_md text, related_links jsonb, is_pinned boolean, sort_order integer, public_updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
 SELECT i.id,r.category_id,r.question,r.answer_md,r.related_links,r.is_pinned,r.sort_order,i.public_updated_at
 FROM public.faq_items i JOIN public.faq_revisions r ON r.id=i.published_revision_id AND r.faq_id=i.id
 JOIN public.faq_categories c ON c.id=r.category_id AND c.is_visible=true
 WHERE i.status='published' AND i.published_revision_id IS NOT NULL
 ORDER BY i.is_pinned DESC,i.sort_order ASC,i.public_updated_at DESC
$function$


;

CREATE OR REPLACE FUNCTION public.faq_admin_categories()
 RETURNS SETOF faq_categories
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN IF NOT public.faq_is_editor() THEN RAISE EXCEPTION 'admin required' USING errcode='42501';END IF;
 RETURN QUERY SELECT * FROM public.faq_categories ORDER BY sort_order,name;
END$function$


;

CREATE OR REPLACE FUNCTION public.faq_admin_list()
 RETURNS TABLE(id uuid, category_id uuid, question text, answer_md text, related_links jsonb, status text, is_pinned boolean, sort_order integer, version integer, created_at timestamp with time zone, updated_at timestamp with time zone, public_updated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN IF NOT public.faq_is_editor() THEN RAISE EXCEPTION 'admin required' USING errcode='42501';END IF;
 RETURN QUERY SELECT i.id,r.category_id,r.question,r.answer_md,r.related_links,i.status,r.is_pinned,r.sort_order,i.version,i.created_at,i.updated_at,i.public_updated_at
 FROM public.faq_items i JOIN public.faq_revisions r ON r.id=i.current_revision_id AND r.faq_id=i.id ORDER BY i.is_pinned DESC,i.sort_order,i.updated_at DESC;
END$function$


;

CREATE OR REPLACE FUNCTION public.faq_history(p_id uuid)
 RETURNS TABLE(id uuid, revision_number integer, question text, answer_md text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN IF NOT public.faq_is_editor() THEN RAISE EXCEPTION 'admin required' USING errcode='42501';END IF;
 RETURN QUERY SELECT r.id,r.revision_number,r.question,r.answer_md,r.created_at FROM public.faq_revisions r WHERE r.faq_id=p_id ORDER BY r.revision_number DESC;
END$function$


;

CREATE OR REPLACE FUNCTION public.faq_save_draft(p_id uuid, p_category_id uuid, p_question text, p_answer_md text, p_related_links jsonb DEFAULT '[]'::jsonb, p_sort_order integer DEFAULT 100, p_is_pinned boolean DEFAULT false, p_expected_version integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id uuid;v_version int;v_revision uuid;v_status text;v_url text;v_entry jsonb;
BEGIN
 IF NOT public.faq_is_editor() THEN RAISE EXCEPTION 'admin required' USING errcode='42501';END IF;
 IF p_question IS NULL OR length(trim(p_question)) NOT BETWEEN 1 AND 200 OR p_answer_md IS NULL OR length(trim(p_answer_md)) NOT BETWEEN 1 AND 10000 THEN RAISE EXCEPTION '질문 또는 답변 길이가 유효하지 않습니다.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.faq_categories WHERE id=p_category_id) THEN RAISE EXCEPTION '카테고리가 존재하지 않습니다.';END IF;
 IF p_sort_order NOT BETWEEN 0 AND 99999 THEN RAISE EXCEPTION '정렬 순서가 유효하지 않습니다.';END IF;
 IF p_related_links IS NULL OR jsonb_typeof(p_related_links)<>'array' OR jsonb_array_length(p_related_links)>10 THEN RAISE EXCEPTION '관련 링크 형식이 유효하지 않습니다.';END IF;
 FOR v_entry IN SELECT value FROM jsonb_array_elements(p_related_links) LOOP
  v_url=v_entry->>'url';
  IF v_url IS NULL OR length(v_url)>2000 OR v_url !~ '^https://[^[:space:]]+$' THEN RAISE EXCEPTION 'https 링크만 허용됩니다.';END IF;
 END LOOP;
 IF p_id IS NULL THEN
  INSERT INTO public.faq_items(category_id,created_by,updated_by,sort_order,is_pinned) VALUES(p_category_id,auth.uid(),auth.uid(),p_sort_order,p_is_pinned) RETURNING id INTO v_id;v_version=0;
 ELSE
  SELECT i.id,i.version,i.status INTO v_id,v_version,v_status FROM public.faq_items i WHERE i.id=p_id FOR UPDATE;
  IF v_id IS NULL THEN RAISE EXCEPTION '질문이 존재하지 않습니다.';END IF;
  IF p_expected_version IS DISTINCT FROM v_version THEN RAISE EXCEPTION '다른 사용자가 먼저 변경했습니다. 화면을 다시 불러오세요.' USING errcode='40001';END IF;
 END IF;
 INSERT INTO public.faq_revisions(faq_id,revision_number,question,answer_md,related_links,category_id,is_pinned,sort_order,changed_by)
 VALUES(v_id,v_version+1,trim(p_question),trim(p_answer_md),p_related_links,p_category_id,p_is_pinned,p_sort_order,auth.uid()) RETURNING id INTO v_revision;
 UPDATE public.faq_items SET current_revision_id=v_revision,version=version+1,updated_at=now(),updated_by=auth.uid() WHERE id=v_id;
 RETURN v_id;
END$function$


;

CREATE OR REPLACE FUNCTION public.faq_publish(p_id uuid, p_expected_version integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v public.faq_items%rowtype;
BEGIN
 IF NOT public.faq_is_editor() THEN RAISE EXCEPTION 'admin required' USING errcode='42501';END IF;
 SELECT * INTO v FROM public.faq_items WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION '질문이 존재하지 않습니다.';END IF;
 IF v.version IS DISTINCT FROM p_expected_version THEN RAISE EXCEPTION '다른 사용자가 먼저 변경했습니다. 다시 불러오세요.' USING errcode='40001';END IF;
 IF v.current_revision_id IS NULL THEN RAISE EXCEPTION '게시할 버전이 없습니다.';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.faq_revisions r JOIN public.faq_categories c ON c.id=r.category_id AND c.is_visible WHERE r.id=v.current_revision_id AND r.faq_id=v.id) THEN RAISE EXCEPTION '비공개 카테고리는 게시할 수 없습니다.';END IF;
 UPDATE public.faq_items SET category_id=(SELECT r.category_id FROM public.faq_revisions r WHERE r.id=v.current_revision_id),
 is_pinned=(SELECT r.is_pinned FROM public.faq_revisions r WHERE r.id=v.current_revision_id),
 sort_order=(SELECT r.sort_order FROM public.faq_revisions r WHERE r.id=v.current_revision_id),
 published_revision_id=v.current_revision_id,status='published',published_at=coalesce(published_at,now()),
 public_updated_at=now(),version=version+1,updated_at=now(),updated_by=auth.uid() WHERE id=p_id;
END$function$


;

CREATE OR REPLACE FUNCTION public.faq_archive(p_id uuid, p_expected_version integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v int;
BEGIN
 IF NOT public.faq_is_editor() THEN RAISE EXCEPTION 'admin required' USING errcode='42501';END IF;
 SELECT version INTO v FROM public.faq_items WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION '질문이 존재하지 않습니다.';END IF;
 IF v IS DISTINCT FROM p_expected_version THEN RAISE EXCEPTION '다른 사용자가 먼저 변경했습니다.' USING errcode='40001';END IF;
 UPDATE public.faq_items SET status='archived',version=version+1,updated_at=now(),updated_by=auth.uid() WHERE id=p_id;
END$function$


;

CREATE OR REPLACE FUNCTION public.faq_restore(p_id uuid, p_revision_id uuid, p_expected_version integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_version int;v_old public.faq_revisions%rowtype;v_new uuid;
BEGIN
 IF NOT public.faq_is_editor() THEN RAISE EXCEPTION 'admin required' USING errcode='42501';END IF;
 SELECT version INTO v_version FROM public.faq_items WHERE id=p_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION '질문이 존재하지 않습니다.';END IF;
 IF v_version IS DISTINCT FROM p_expected_version THEN RAISE EXCEPTION '다른 사용자가 먼저 변경했습니다.' USING errcode='40001';END IF;
 SELECT * INTO v_old FROM public.faq_revisions WHERE id=p_revision_id AND faq_id=p_id;
 IF NOT FOUND THEN RAISE EXCEPTION '복원할 이전 버전이 존재하지 않습니다.';END IF;
 INSERT INTO public.faq_revisions(faq_id,revision_number,question,answer_md,related_links,category_id,is_pinned,sort_order,changed_by,change_note)
 VALUES(p_id,v_version+1,v_old.question,v_old.answer_md,v_old.related_links,v_old.category_id,v_old.is_pinned,v_old.sort_order,auth.uid(),'restore from revision '||v_old.revision_number) RETURNING id INTO v_new;
 UPDATE public.faq_items SET current_revision_id=v_new,version=version+1,updated_at=now(),updated_by=auth.uid() WHERE id=p_id;
END$function$


;

CREATE OR REPLACE FUNCTION public.faq_category_save(p_id uuid, p_slug text, p_name text, p_sort_order integer DEFAULT 100, p_is_visible boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id uuid;
BEGIN
 IF NOT public.faq_is_editor() THEN RAISE EXCEPTION 'admin required' USING errcode='42501';END IF;
 IF p_slug !~ '^[a-z0-9-]{2,50}$' OR length(trim(p_name)) NOT BETWEEN 1 AND 70 OR p_sort_order NOT BETWEEN 0 AND 99999 THEN RAISE EXCEPTION '잘못된 카테고리 입력입니다.';END IF;
 IF p_id IS NULL THEN INSERT INTO public.faq_categories(slug,name,sort_order,is_visible) VALUES(p_slug,trim(p_name),p_sort_order,p_is_visible) RETURNING id INTO v_id;
 ELSE UPDATE public.faq_categories SET slug=p_slug,name=trim(p_name),sort_order=p_sort_order,is_visible=p_is_visible,updated_at=now() WHERE id=p_id RETURNING id INTO v_id;
 IF v_id IS NULL THEN RAISE EXCEPTION '카테고리가 존재하지 않습니다.';END IF;END IF;
 RETURN v_id;
END$function$


;

CREATE OR REPLACE FUNCTION public.faq_login_allow(p_key_hash text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE blocked boolean;
BEGIN
 IF p_key_hash !~ '^[0-9a-f]{64}$' THEN RETURN false;END IF;
 SELECT (blocked_until>now() OR (window_started_at>now()-interval '15 minutes' AND failure_count>=8))
 INTO blocked FROM public.faq_login_attempts WHERE key_hash=p_key_hash;
 RETURN NOT coalesce(blocked,false);
END$function$


;

CREATE OR REPLACE FUNCTION public.faq_login_failure(p_key_hash text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
 IF p_key_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'invalid throttle key';END IF;
 INSERT INTO public.faq_login_attempts(key_hash,failure_count,window_started_at,blocked_until)
 VALUES(p_key_hash,1,now(),null)
 ON CONFLICT(key_hash) DO UPDATE SET
 failure_count=CASE WHEN faq_login_attempts.window_started_at < now()-interval '15 minutes' THEN 1 ELSE faq_login_attempts.failure_count+1 END,
 window_started_at=CASE WHEN faq_login_attempts.window_started_at < now()-interval '15 minutes' THEN now() ELSE faq_login_attempts.window_started_at END,
 blocked_until=CASE WHEN faq_login_attempts.window_started_at < now()-interval '15 minutes' THEN null
 WHEN faq_login_attempts.failure_count+1>=8 THEN now()+interval '15 minutes' ELSE faq_login_attempts.blocked_until END;
END$function$


;

CREATE OR REPLACE FUNCTION public.faq_login_success(p_key_hash text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
 IF p_key_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'invalid throttle key';END IF;
 DELETE FROM public.faq_login_attempts WHERE key_hash=p_key_hash;
END$function$
;

REVOKE EXECUTE ON FUNCTION public.faq_my_role() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_is_editor() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_is_owner() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_public_categories() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_public_list() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_admin_categories() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_admin_list() FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_history(uuid) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_save_draft(uuid,uuid,text,text,jsonb,int,boolean,int) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_publish(uuid,int) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_archive(uuid,int) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_restore(uuid,uuid,int) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_category_save(uuid,text,text,int,boolean) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_login_allow(text) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_login_failure(text) FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.faq_login_success(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.faq_public_categories(),public.faq_public_list() TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.faq_my_role(),public.faq_admin_categories(),public.faq_admin_list(),
 public.faq_history(uuid),public.faq_save_draft(uuid,uuid,text,text,jsonb,int,boolean,int),public.faq_publish(uuid,int),
 public.faq_archive(uuid,int),public.faq_restore(uuid,uuid,int),public.faq_category_save(uuid,text,text,int,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.faq_login_allow(text),public.faq_login_failure(text),public.faq_login_success(text) TO service_role;
INSERT INTO public.faq_categories(slug,name,sort_order) VALUES
('operations','동아리 활동 및 운영',1),('funding','지원금 사용',2),('settlement','법인카드·정산',3),
('report','활동보고 및 제출',4),('monitoring','모니터링 일정',5),('other','기타 문의',6);
