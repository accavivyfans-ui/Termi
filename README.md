# Termi — iOS SSH 클라이언트

아이디/비밀번호 또는 SSH 키(ED25519/RSA, 생성·파일 가져오기·.pub 내보내기) 접속, 호스트 저장(키체인), 서버 키 확인, 다중 세션, 테마/글자 크기.
엔진: SwiftTerm(터미널) + Citadel(SSH). iOS 17+.

## IPA 받기 (Mac 없이)
1. GitHub에 새 레포를 만들고 이 폴더 내용을 그대로 올립니다 (.github 폴더 포함).
2. Actions 탭 → "Build IPA" → Run workflow (main에 push해도 자동 실행).
3. 끝나면 Releases → latest 에서 Termi.ipa 바로 다운로드.
4. Sideloadly / AltStore 등으로 본인 Apple ID 서명해서 설치.

## Mac에서 직접 빌드
brew install xcodegen && xcodegen generate && open Termi.xcodeproj
(Xcode 26 이상 필요)
