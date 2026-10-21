# FAQ 관리자 로딩 오류 수정 (2026-10-21)

## 발견
- 관리자 실제 사번+비밀번호 로그인 성공 후 UI에서 "질문 불러오는 중" 무한 표시 및 "로그인 실패: 요청 처리에 실패했습니다." 오안내.
- FAQ Edge Function 호출: 로그인과 역할 확인 HTTP 200, 관리자 FAQ 목록 조회 HTTP 400.
- PostgreSQL 로그: `column reference "r.id" is ambiguous`.
- 원인: `faq_admin_action` PL/pgSQL 레코드 변수 `i`, `r`와 SELECT 문의 테이블 별칭 `i`, `r`가 겹침.

## 변경 (FAQ 프로젝트에만 적용)
1. DB 함수의 레코드 변수를 `v_item_row`, `v_revision_row`로 변경. 테이블 별칭과 SQL/권한 규칙은 유지.
2. 수정된 함수 전체 정의를 `supabase/migrations/20261021_faq_fix_admin_action_aliases.sql`에 기록.
3. 로그인 인증과 자료 조회 실패 메시지를 분리하고, 로딩 실패 시 다시 시도 안내 제공.
4. 이름 충돌 및 사용자 오류 표시 회귀 테스트 추가.

## 실제 확인
- FAQ 관리자 1명, 유효한 세션 1건 존재 확인. 비밀번호를 열람하거나 수정하지 않음.
- 활성 관리자 세션으로 `faq_admin_action('list')` → 빈 배열 정상.
- `faq_admin_action('categories')` → 6개 정상.
- DB 트랜잭션 내부에서 임시 FAQ 생성→게시→수정→수정 이력→복원→비공개→재게시 성공 후 `ROLLBACK`.
- 롤백 이후 FAQ·수정 이력·학생 공개 질문 모두 0건 유지.
- GitHub Actions JavaScript 및 추가 회귀 테스트 + GitHub Pages 배포는 변경 커밋의 Actions 결과에서 재확인.
- 실제 브라우저 재진입·기능 확인은 담당자가 새로고침 후 확인해야 최종 완료 판단 가능.

## 변경하지 않은 대상
- 관리자 등록정보·비밀번호·로그인 비밀값
- 기존 동아리 메인/자료실/모니터링 시스템 저장소 및 DB
- 학생 FAQ 공개 콘텐츠


## 2026-10-21 게시·임시저장 관련 링크 URL 오류 수정

- 현상: 관리자 화면에서 관련 링크를 작성하고 '게시하기'를 누르면 '게시 실패: 입력값 또는 기존 비밀번호를 확인해 주세요.' 발생.
- 운영 로그: PostgreSQL `invalid regular expression: invalid repetition count(s)`; Edge Function `faq-admin` HTTP 400.
- 원인: `faq_admin_action` 의 관련 링크 검증 정규식에 `{1,1992}` 반복 수량을 사용하여 PostgreSQL에서 정규식 컴파일 실패.
- 수정: HTTPS 형식 체크 `^https://[^[:space:]]+$`와 길이 제한 `<=2000`을 분리. 운영 FAQ DB 마이그레이션 적용.
- 검증: 활성 관리자 세션의 임시 트랜잭션 내에서 HTTPS 링크를 포함한 질문 임시저장→학생 비노출→게시→수정→이력→복원→비공개→재게시 전 단계 통과. 최종 `ROLLBACK` 후 FAQ 0건, 수정이력 0건 확인.
- 운영 사용자 계정·비밀번호·비밀값은 변경하지 않음. 기존 메인/자료실/모니터링도 변경 없음.
- 별도 개선: 저장과 비밀번호 변경 오류 메시지를 분리하고, 게시 완료 시 학생용 화면 확인 방법 안내.
- 실제 브라우저에서 담당자가 다시 게시하는 최종 확인은 별도 필요.
