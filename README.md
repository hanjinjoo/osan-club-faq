# 오산대학교 동아리 FAQ
학생 공개 FAQ + 단일 담당자 관리자 페이지.

## 연결 현황 (2026-10-21)
- GitHub Pages 공개 프런트엔드: `/`
- 관리자: `/admin/`
- FAQ 독립 Supabase 프로젝트: `achfgdunjdjztxsxneam`
- 학생 목록은 **DB에서 게시된 문항만** 불러옵니다. 예시 질문을 실제 게시글로 오인하지 않습니다.
- 관리자 기능: 사번+별도 비밀번호, 초안 등록·수정·게시·비공개·수정이력·복원·카테고리 관리·비밀번호 변경.
- 기존 모니터링 데이터베이스와 저장소는 **변경하지 않았습니다**.
- 이전 v0.2 원본 ZIP은 ChatGPT 파일 라이브러리에 보존되어 있으며, 이 저장소의 화면은 해당 설계를 기준으로 복구·구현했습니다. 원본 파일 구조와 현재 배포 코드가 완전히 동일하다는 뜻은 아닙니다.

## 운영 활성화에 필요한 마지막 설정
1. [FAQ 프로젝트 Authentication > Providers](https://supabase.com/dashboard/project/achfgdunjdjztxsxneam/auth/providers)에서 공개 이메일 회원가입 비활성화.
2. Authentication > Users에서 담당자용 이메일·비밀번호 사용자 1명을 생성하고 이메일을 확인 처리. 이메일은 관리자 로그인 화면에서 받지 않습니다.
3. FAQ DB에서만 해당 Auth UUID와 실제 사번을 매핑:
   ```sql
   insert into public.faq_admins(user_id,employee_no,role,is_active)
   values ('<AUTH_USER_UUID>','<EMPLOYEE_NUMBER>','owner',true);
   ```
   사번과 비밀번호는 **GitHub 또는 문서에 실제 값으로 입력하지 마세요**.
4. [FAQ Edge Functions Secrets](https://supabase.com/dashboard/project/achfgdunjdjztxsxneam/settings/functions)에서 `FAQ_LOGIN_PEPPER`를 랜덤한 32자 이상 비밀값으로 추가. 이것은 공개 JavaScript에 절대 작성하지 마세요. `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`는 Supabase 런타임이 제공합니다.
5. 로그인 → 임시저장 → 게시 → 학생 노출 → 비공개 → 수정이력 → 복원을 차례대로 실환경 확인.
6. 실제 검증 완료 전에는 통합 메인 사이트에 FAQ 링크를 추가하지 마세요.

## DB·보안
- 학생에게는 `faq_public_list` RPC의 게시 버전만 전달.
- 모든 FAQ DB 테이블 RLS 활성화 및 anon/authenticated 직접 접근 차단.
- DB 관리자 RPC는 매번 Auth JWT와 활성 담당자 매핑 확인.
- 로그인 서버 함수 `faq-login`은 암호를 Auth에서 검증하며 8회 실패 시 15분 제한.
- 자격 증명은 코드에 존재하지 않습니다.
- URL 간 탐색은 `target="_blank"`, `rel="noopener noreferrer"` 사용.
- 공급망 의존성: supabase-js 2.79.0 고정 버전.

## 향후 범위
PPT/PDF 접수와 동아리별 보관·제출/미제출 현황은 별도 후속 단계. 아직 본 앱에 구현되지 않았습니다.
