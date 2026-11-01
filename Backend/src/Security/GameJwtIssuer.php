<?php
declare(strict_types=1);

namespace StudyGo\Security;

/**
 * Issues short-lived game access JWTs after the caller has authenticated the
 * StudyGo account and verified that the user may enter the requested server.
 *
 * The secret must be shared with GameServer through server-side secret storage.
 * Never expose it to Flutter/Unity or return it to the client.
 */
final class GameJwtIssuer
{
    public function __construct(
        private readonly string $secret,
        private readonly string $issuer,
        private readonly string $audience,
        private readonly int $ttlSeconds = 900
    ) {
        if (strlen($this->secret) < 32) {
            throw new \InvalidArgumentException('Game JWT secret must be at least 32 bytes.');
        }
        if ($this->issuer === '' || $this->audience === '') {
            throw new \InvalidArgumentException('JWT issuer and audience are required.');
        }
        if ($this->ttlSeconds < 60 || $this->ttlSeconds > 3600) {
            throw new \InvalidArgumentException('JWT lifetime must be between 60 and 3600 seconds.');
        }
    }

    public function issue(int $studyGoUserId, string $authorizedServerId): string
    {
        if ($studyGoUserId <= 0) {
            throw new \InvalidArgumentException('Invalid StudyGo user ID.');
        }
        if (!preg_match('/^[A-Za-z0-9_-]{1,48}$/', $authorizedServerId)) {
            throw new \InvalidArgumentException('Invalid server ID.');
        }

        $now = time();
        $header = ['typ' => 'JWT', 'alg' => 'HS256'];
        $payload = [
            'iss' => $this->issuer,
            'aud' => $this->audience,
            'sub' => (string) $studyGoUserId,
            'server_id' => $authorizedServerId,
            'iat' => $now,
            'nbf' => $now - 5,
            'exp' => $now + $this->ttlSeconds,
            'jti' => bin2hex(random_bytes(16)),
        ];

        $encodedHeader = $this->base64UrlEncode(json_encode($header, JSON_THROW_ON_ERROR));
        $encodedPayload = $this->base64UrlEncode(json_encode($payload, JSON_THROW_ON_ERROR));
        $signingInput = $encodedHeader . '.' . $encodedPayload;
        $signature = hash_hmac('sha256', $signingInput, $this->secret, true);

        return $signingInput . '.' . $this->base64UrlEncode($signature);
    }

    private function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
