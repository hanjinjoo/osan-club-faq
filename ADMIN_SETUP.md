# FAQ 운영 개통 — 담당자 설정 및 테스트

> 작업 대상 **FAQ 전용** Supabase 프로젝트 `achfgdunjdjztxsxneam`만.
> 예약/모니터링 Supabase `irqovqzrdvqmuuuvxcmt`에는 절대 적용하지 않습니다.
> 공개 GitHub 또는 채팅에 **비밀번호, 실제 사번, OTP, 서비스 비밀키, PEPPER**를 쓰지 마세요.

## 1. 시작 전 검증 (2026-10-21)

- FAQ 프로젝트: ACTIVE_HEALTHY.
- Auth 사용자: 0명.
- `faq_admins`: 0명.
- FAQ 카테고리: 6개.
- FAQ 게시/임시저장/이력: 0건.
- Edge Function `faq-login`: 배포됨(설정은 아직 미확인).
- 학생의 관리자 테이블 직접 SELECT / 관리자 RPC 호출 권한은 차단됨.
- 소유자 없는 요청으로 관리자 조회 및 임시저장 시도하면 권한 오류 발생(읽기 안전 검사 통과).
- 비밀값 등록 여부 및 실제 로그인은 미검증.

## 2. Authentication 계정 생성 — 사용자가 직접 수행

1. 반드시 [FAQ 전용 프로젝트 사용자 관리](https://supabase.com/dashboard/project/achfgdunjdjztxsxneam/auth/users)인지 확인합니다.
2. Auth > Providers(Email) 등의 설정에서 공개 신규 회원가입을 비활성화하고, **기존 사용자 이메일+비밀번호 로그인**은 허용합니다. Supabase 버전에 따라 메뉴명이 달라질 수 있습니다.
3. Users > Add user에서 관리 전용 이메일과 **새 강력한 비밀번호(12자 이상 권장)**를 사용해 단 한 명의 사용자를 추가합니다. 이메일 확인 상태를 완료로 설정하거나 공식 확인 절차를 끝냅니다.
4. 생성된 사용자의 **UID(UUID)**를 확인합니다. 로그인 화면에는 이메일을 입력하지 않고, 내부적으로 서버가 사번→이 Auth 계정으로 매핑합니다.
5. 비밀번호/이메일/사번을 채팅 또는 GitHub 저장소에 기록하지 마세요.

## 3. 사번과 Auth UID 연결 — SQL Editor에서만 수행

[FAQ 전용 SQL Editor](https://supabase.com/dashboard/project/achfgdunjdjztxsxneam/sql/new)를 열어 본인이 확인한 UID와 실제 사번을 아래의 자리표시자에 직접 입력합니다.
사번은 숫자만 4~16자리입니다. **실제 값으로 치환한 SQL을 이 채팅에 공유하지 마세요**.

```sql
-- ★ 이 쿼리는 achfgdunjdjztxsxneam FAQ 전용 프로젝트에서만 실행 ★
INSERT INTO public.faq_admins (user_id, employee_no, role, is_active)
VALUES (
  '<AUTH_UID_UUID>'::uuid,
  '<NUMERIC_EMPLOYEE_NO>',
  'owner',
  true
);
```

관리자 테이블은 단일 계정만 허용하도록 제약이 걸려 있습니다. 오류가 발생하면 같은 쿼리를 반복 실행하거나 기존 행을 삭제하지 말고 원인을 먼저 확인합니다.

등록 후 비밀값을 출력하지 않는 검증 쿼리:

```sql
SELECT (SELECT COUNT(*) FROM auth.users) AS auth_users,
       (SELECT COUNT(*) FROM public.faq_admins WHERE is_active) AS active_faq_admins;
```

정상 초기 상태는 두 값 모두 1이어야 합니다.

## 4. Edge Function의 별도 비밀값 등록

[FAQ Edge Functions Secrets](https://supabase.com/dashboard/project/achfgdunjdjztxsxneam/functions/secrets)에서 다음 사용자 정의 비밀값을 추가합니다.

- Name: `FAQ_LOGIN_PEPPER`
- Value: **비밀번호 관리자나 암호학적 난수 생성기로 생성한 임의의 32자 이상 문자열**
- 실제 Value는 공개 저장소·화면 캡처·채팅에 공유하지 않습니다.

참고: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`는 Supabase에서 Edge Function 런타임에 제공하는 변수입니다. 누락되었다면 별도로 점검해야 합니다. **서비스 역할 키를 GitHub의 config.js 등에 넣지 마세요.**

## 5. 직접 운영 테스트

[관리자 페이지](https://hanjinjoo.github.io/osan-club-faq/admin/)에서 사번과 전용 비밀번호로 로그인합니다.

1. **로그인**: 정확한 자격 증명만 성공하고 잘못된 비밀번호는 거절.
2. **등록**: 승인된 검증용 제목/답변을 임시저장하면 학생 화면에는 노출되지 않는지 확인.
3. **게시**: 게시 후 [학생 페이지](https://hanjinjoo.github.io/osan-club-faq/)의 검색·분류·아코디언에서 정상 표시되는지 확인.
4. **수정**: 게시 문항을 수정한 뒤 임시저장. 재게시 전까지 학생에게는 종전 게시 버전이 보이는지 확인.
5. **재게시/비공개**: 재게시하면 변경된 답변이 보이고 비공개하면 학생 목록에서 사라지는지 확인.
6. **복원**: 수정 이력에서 과거 버전 선택·복원, 재게시 전에는 학생에게 나타나지 않는지 확인.
7. **권한**: 비로그인 상태에서 관리자 RPC 쓰기가 차단되는지 확인.
8. **정리**: 승인 없는 테스트 문항은 비공개로 유지하고, 실제 운영용 게시 전에 담당자가 내용 확인.

오류 발생 시 브라우저 Console/Network의 **HTTP 상태 및 오류 문구만** 공유합니다. 인증 토큰·비밀번호·실제 사번은 가립니다.

## 6. 운영 완료 기준

- 관리자 Auth 계정 1명, `faq_admins` 활성 담당자 1명.
- `FAQ_LOGIN_PEPPER` 등록되어 Edge Function이 정상 응답.
- 관리 페이지 로그인, 질문 임시저장·게시·수정·비공개·복원 실제 확인.
- 학생의 비공개 데이터 접근 불가 확인.
- 기존 자료실·메인·모니터링 DB 미변경.
- 완료 전에는 '운영 검증 완료'라고 보고하지 않음.

## 후속 개발

PPT/PDF 파일 접수·동아리별 보관·제출 및 미제출 현황은 사용자와 단계별 사전 협의 후 별도로 설계.
