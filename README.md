# 오산대학교 동아리 FAQ

**학생 공개 열람 + 이메일 없는 사번·비밀번호 단일 관리자 시스템** (2026-10-21 기준)

- 학생용: https://hanjinjoo.github.io/osan-club-faq/
- 관리자: https://hanjinjoo.github.io/osan-club-faq/admin/
- 메인 포털: https://hanjinjoo.github.io/osan-club/
- **FAQ 전용** Supabase 프로젝트: `achfgdunjdjztxsxneam`
- 운영 중인 모니터링 Supabase `irqovqzrdvqmuuuvxcmt`와 기존 메인·자료실 소스는 변경하지 않았습니다.

## 관리자 인증

- 이메일 / Supabase Auth 사용자 계정 **필요 없음**.
- 사번(4~16자리 숫자) + 별도 비밀번호(최소 12자)를 이용합니다.
- 최초 등록에는 Supabase Secrets에 별도로 보관한 1회 등록 코드가 필요합니다.
- 비밀번호는 bcrypt 해시로 DB에만 저장하고, 익명 브라우저가 해시를 조회할 수 없습니다.
- 관리자 임시 세션은 8시간 만료 / 로그아웃 가능 / 비밀번호 변경 시 다른 세션 철회.
- 학생은 로그인 없이 게시된 질문만 검색·분류별 조회할 수 있습니다.
- 질문 임시저장·게시·수정·비공개·수정 이력·버전 복원·카테고리 변경은 관리자 인증을 거친 서버에서만 처리합니다.

**다음 단계(사용자 설정 필요):** [ADMIN_SETUP.md](./ADMIN_SETUP.md)에 따라 FAQ 전용 Edge Function Secrets에 `FAQ_LOGIN_PEPPER`, `FAQ_BOOTSTRAP_SECRET`을 각각 서로 다른 32자 이상의 무작위 값으로 추가하고, 관리자 페이지에서 실제 사번·비밀번호를 1회 등록하세요. 이메일 주소를 입력할 필요가 없습니다.

> **현재 미검증:** 실제 비밀값 등록, 첫 관리자 가입, 로그인 및 FAQ 등록·게시·복원 실사용 흐름. 이 설정은 완료 전까지 운영 완료라고 보고하지 않습니다.

## 기술

- GitHub Pages 정적 학생/관리자 화면: `index.html`, `admin/index.html`
- Supabase PostgreSQL: `faq_categories`, `faq_admins`, `faq_items`, `faq_revisions`, `faq_sessions`, `faq_login_attempts`
- Supabase `faq-admin` Edge Function: 인증, 세션 발급, API 진입점. 서버 역할 키와 비밀값은 공개 저장소에 없음.
- 기존 `faq-login` 엔드포인트는 HTTP 410으로 폐기.
- 학생 공개 목록: `faq_public_categories()`, `faq_public_list()` RPC
- 신규 관리자 쓰기: `faq_admin_action` 등은 **서버 역할만** 실행 가능.
- 복구 가능한 스키마 및 함수 원본은 `supabase/migrations/`에 저장.
- GitHub Actions는 JavaScript 구문 검사와 추가 보안 구조 테스트를 실행하고, Pages는 `main/(root)`에서 자동 배포.

## 변경 이력 및 향후 범위

- 이메일 기반 인증 설계를 담당자 요청에 따라 폐기하고 독립 사번+비밀번호 인증으로 재개발했습니다.
- 원래 v0.2 ZIP은 파일 라이브러리에 따로 보관되어 있으며, 현재 운영 코드는 해당 설계 기준 재구성본입니다.
- PPT/PDF 접수, 동아리별 보관, 제출/미제출 현황은 사용자 승인 후 **별도 단계**로 진행합니다.
