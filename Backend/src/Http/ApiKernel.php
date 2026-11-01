<?php
declare(strict_types=1);

namespace StudyGo\Http;

use PDO;
use StudyGo\Security\GameJwtIssuer;

final class ApiKernel
{
    public function __construct(private array $config, private PDO $pdo) {}

    public function handle(): void
    {
        header('Content-Type: application/json; charset=utf-8');
        header('Cache-Control: no-store');
        $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
        $allowed = $this->config['app']['allowed_origins'] ?? [];
        if ($origin !== '' && in_array($origin, $allowed, true)) {
            header('Access-Control-Allow-Origin: ' . $origin);
            header('Vary: Origin');
            header('Access-Control-Allow-Headers: Content-Type, Authorization');
            header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
        }
        if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') { http_response_code(204); return; }

        try {
            $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
            $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
            $body = $this->jsonBody();

            if ($method === 'GET' && $path === '/health') {
                $this->respond(200, ['status' => 'ok', 'service' => 'studygo-api']);
            } elseif ($method === 'POST' && $path === '/api/v1/auth/register') {
                $this->register($body);
            } elseif ($method === 'POST' && $path === '/api/v1/auth/login') {
                $this->login($body);
            } elseif ($method === 'GET' && $path === '/api/v1/auth/me') {
                $this->me();
            } elseif ($method === 'POST' && $path === '/api/v1/game/token') {
                $this->gameToken($body);
            } else {
                $this->respond(404, ['error' => 'not_found']);
            }
        } catch (\InvalidArgumentException $e) {
            $this->respond(422, ['error' => $e->getMessage()]);
        } catch (\PDOException $e) {
            if ($e->getCode() === '23000') $this->respond(409, ['error' => 'account_already_exists']);
            else { error_log($e->getMessage()); $this->respond(500, ['error' => 'internal_error']); }
        } catch (\Throwable $e) {
            error_log($e->getMessage());
            $this->respond(500, ['error' => 'internal_error']);
        }
    }

    private function register(array $b): void
    {
        $email = strtolower(trim((string)($b['email'] ?? '')));
        $password = (string)($b['password'] ?? '');
        $name = trim((string)($b['displayName'] ?? ''));
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 190) throw new \InvalidArgumentException('invalid_email');
        if (strlen($password) < 10 || strlen($password) > 200) throw new \InvalidArgumentException('password_must_be_10_to_200_characters');
        if ($name === '' || mb_strlen($name) > 80) throw new \InvalidArgumentException('invalid_display_name');

        $q = $this->pdo->prepare("INSERT INTO studygo_users(email,password_hash,display_name) VALUES(?,?,?)");
        $q->execute([$email, password_hash($password, PASSWORD_DEFAULT), $name]);
        $id = (int)$this->pdo->lastInsertId();
        $this->respond(201, ['user' => ['id' => $id, 'email' => $email, 'displayName' => $name], 'message' => 'account_created_login_required']);
    }

    private function login(array $b): void
    {
        $email = strtolower(trim((string)($b['email'] ?? '')));
        $password = (string)($b['password'] ?? '');
        $q = $this->pdo->prepare("SELECT id,email,password_hash,display_name,account_status FROM studygo_users WHERE email=? LIMIT 1");
        $q->execute([$email]);
        $user = $q->fetch();
        if (!$user || !password_verify($password, $user['password_hash'])) {
            $this->respond(401, ['error' => 'invalid_credentials']); return;
        }
        if ($user['account_status'] !== 'active') { $this->respond(403, ['error' => 'account_not_active']); return; }
        if (password_needs_rehash($user['password_hash'], PASSWORD_DEFAULT)) {
            $u = $this->pdo->prepare("UPDATE studygo_users SET password_hash=? WHERE id=?");
            $u->execute([password_hash($password, PASSWORD_DEFAULT), $user['id']]);
        }
        $this->pdo->prepare("UPDATE studygo_users SET last_login_at=UTC_TIMESTAMP() WHERE id=?")->execute([$user['id']]);
        $access = $this->randomToken(32);
        $refresh = $this->randomToken(48);
        $accessHash = hash('sha256', $access);
        $refreshHash = hash('sha256', $refresh);
        $days = (int)($this->config['auth']['refresh_ttl_days'] ?? 30);
        $ins = $this->pdo->prepare("INSERT INTO studygo_refresh_tokens(user_id,token_hash,expires_at) VALUES(?,?,DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? DAY))");
        $ins->execute([$user['id'], $refreshHash, $days]);
        // Access token is opaque and stored hashed; default lifetime 15 minutes.
        $this->pdo->prepare("INSERT INTO studygo_refresh_tokens(user_id,token_hash,expires_at) VALUES(?,?,DATE_ADD(UTC_TIMESTAMP(), INTERVAL 15 MINUTE))")->execute([$user['id'], $accessHash]);
        $this->respond(200, [
            'user' => ['id' => (int)$user['id'], 'email' => $user['email'], 'displayName' => $user['display_name']],
            'accessToken' => $access, 'tokenType' => 'Bearer', 'expiresIn' => 900, 'refreshToken' => $refresh
        ]);
    }

    private function me(): void
    {
        $user = $this->authenticatedUser();
        $this->respond(200, ['user' => ['id' => (int)$user['id'], 'email' => $user['email'], 'displayName' => $user['display_name']]]);
    }

    private function gameToken(array $b): void
    {
        $user = $this->authenticatedUser();
        $serverId = trim((string)($b['serverId'] ?? ''));
        if (!preg_match('/^[A-Za-z0-9_-]{1,48}$/', $serverId)) throw new \InvalidArgumentException('invalid_server_id');
        $q = $this->pdo->prepare("SELECT s.server_status, m.membership_status FROM game_servers s JOIN game_server_members m ON m.server_id=s.server_id WHERE s.server_id=? AND m.user_id=? LIMIT 1");
        $q->execute([$serverId, $user['id']]);
        $membership = $q->fetch();
        if (!$membership || $membership['membership_status'] !== 'active' || !in_array($membership['server_status'], ['open','protected','transfer_locked'], true)) {
            $this->respond(403, ['error' => 'server_access_denied']); return;
        }
        $secret = (string)($this->config['game_jwt']['secret'] ?? '');
        $issuer = new GameJwtIssuer($secret, (string)$this->config['game_jwt']['issuer'], (string)$this->config['game_jwt']['audience'], (int)$this->config['game_jwt']['ttl']);
        $token = $issuer->issue((int)$user['id'], $serverId);
        $this->respond(200, ['token' => $token, 'tokenType' => 'Bearer', 'expiresIn' => (int)$this->config['game_jwt']['ttl'], 'serverId' => $serverId]);
    }

    private function authenticatedUser(): array
    {
        $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
        if (!preg_match('/^Bearer\s+([A-Za-z0-9_-]{40,100})$/i', $header, $m)) { $this->respond(401, ['error' => 'unauthorized']); exit; }
        $hash = hash('sha256', $m[1]);
        $q = $this->pdo->prepare("SELECT u.id,u.email,u.display_name FROM studygo_refresh_tokens t JOIN studygo_users u ON u.id=t.user_id WHERE t.token_hash=? AND t.revoked_at IS NULL AND t.expires_at>UTC_TIMESTAMP() AND u.account_status='active' LIMIT 1");
        $q->execute([$hash]);
        $user = $q->fetch();
        if (!$user) { $this->respond(401, ['error' => 'invalid_or_expired_token']); exit; }
        return $user;
    }

    private function jsonBody(): array
    {
        $raw = file_get_contents('php://input') ?: '';
        if ($raw === '') return [];
        $data = json_decode($raw, true);
        if (!is_array($data)) throw new \InvalidArgumentException('invalid_json_body');
        return $data;
    }

    private function randomToken(int $bytes): string { return rtrim(strtr(base64_encode(random_bytes($bytes)), '+/', '-_'), '='); }
    private function respond(int $status, array $data): void { http_response_code($status); echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE); }
}
