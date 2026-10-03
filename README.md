# idira-portkey-claude

Lab test tích hợp giữa **CyberArk Identity (idira)**, **Portkey AI Gateway**, và
**Claude Code** — dùng JWT lấy từ CyberArk Identity (qua OAuth2 Authorization
Code + PKCE, không cần client_secret) để authen trực tiếp với Portkey thay
cho API key tĩnh, sau đó wire JWT đó vào Claude Code để gọi LLM thực tế
(Bedrock, qua Portkey routing).

## Luồng hoạt động

1. `idira-get-jwt.sh` mở browser, xác thực SSO/MFA qua CyberArk Identity
   (Authorization Code + PKCE, public client), đổi code lấy JWT.
2. JWT được dùng làm `Authorization: Bearer` khi gọi Portkey AI Gateway —
   Portkey verify signature qua JWKS và đọc custom claims
   (`portkey_oid`, `portkey_workspace`, `scope`) để xác định org/workspace.
3. Claude Code gọi `idira-get-jwt.sh` làm `apiKeyHelper` (xem
   `.claude/settings.local.json`) để tự động lấy/cache JWT, route request
   qua Portkey tới model Bedrock.

## Giới hạn - đọc trước khi dùng

Các tham số trong `idira-get-jwt.sh` (`CLIENT_ID`, `AUTHORIZE_URL`,
`TOKEN_URL`) và trong `.claude/settings.local.json` (Portkey config slug)
được build riêng theo **môi trường lab hiện có** — 1 tenant CyberArk Identity
và 1 workspace Portkey cụ thể. Clone repo về chạy thẳng sẽ **không hoạt
động** nếu không có account trong lab này.

Muốn test nhanh, liên hệ huydd@huydo.net để được đăng ký account test.

## Cài đặt

```bash
git clone git@github.com:huydd79/idira-portkey-claude.git
cd idira-portkey-claude
./install.sh
```

`install.sh` kiểm tra các tool cần (`curl`, `jq`, `nc`, `openssl`; tự
`brew install` nếu thiếu và máy có Homebrew), sau đó symlink
`idira-get-jwt.sh` vào `~/.local/bin` để gọi được từ bất kỳ đâu.

## Cách dùng

```bash
idira-get-jwt.sh
```

Lần đầu (hoặc khi token hết hạn sau 5h) sẽ tự mở browser để đăng nhập
SSO/MFA. JWT được cache tại `~/.cache/idira_auth/tokens.json`, in ra stdout
để dùng làm Bearer token hoặc làm `apiKeyHelper` cho Claude Code.

Mở Claude Code trong thư mục này (`idira-portkey-claude/`) sẽ tự dùng cấu
hình trong `.claude/settings.local.json` để gọi Claude qua Portkey bằng JWT.
