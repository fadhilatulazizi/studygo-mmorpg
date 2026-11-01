<?php
declare(strict_types=1);
namespace StudyGo\Ads;

/** Google AdMob rewarded SSV ECDSA verifier. Preserves the original signed query bytes. */
final class AdMobSsvVerifier
{
    private const KEY_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json';
    private const CACHE_TTL = 82800; // 23h; Google requires less than 24h.

    public function verify(string $queryString): array
    {
        if ($queryString === '' || strlen($queryString) > 8192) throw new \InvalidArgumentException('invalid_ssv_query');
        $sigPos = strpos($queryString, 'signature=');
        if ($sigPos === false || $sigPos === 0 || $queryString[$sigPos - 1] !== '&') throw new \RuntimeException('ssv_signature_parameters_missing');
        $signedData = substr($queryString, 0, $sigPos - 1);
        $tail = substr($queryString, $sigPos + 10);
        $marker = strpos($tail, '&key_id=');
        if ($marker === false) throw new \RuntimeException('invalid_ssv_signature_format');
        $sigText = substr($tail, 0, $marker);
        $keyId = substr($tail, $marker + 8);
        if ($sigText === '' || !preg_match('/^\d{1,20}$/', $keyId) || str_contains($keyId, '&')) throw new \RuntimeException('invalid_ssv_signature_format');
        $signature = base64_decode(strtr($sigText, '-_', '+/') . str_repeat('=', (4 - strlen($sigText) % 4) % 4), true);
        if ($signature === false) throw new \RuntimeException('invalid_ssv_signature_encoding');

        $keys = $this->publicKeys();
        $pem = $keys[$keyId] ?? null;
        if (!is_string($pem)) { $keys = $this->publicKeys(true); $pem = $keys[$keyId] ?? null; }
        if (!is_string($pem)) throw new \RuntimeException('unknown_admob_key_id');
        $publicKey = openssl_pkey_get_public($pem);
        if ($publicKey === false) throw new \RuntimeException('invalid_admob_public_key');
        if (openssl_verify($signedData, $signature, $publicKey, OPENSSL_ALGO_SHA256) !== 1) throw new \RuntimeException('invalid_admob_signature');

        parse_str($queryString, $params);
        foreach (['ad_unit','reward_amount','reward_item','timestamp','transaction_id','user_id'] as $required) {
            if (!isset($params[$required]) || $params[$required] === '') throw new \InvalidArgumentException('ssv_missing_' . $required);
        }
        return $params;
    }

    private function publicKeys(bool $force = false): array
    {
        $cache = sys_get_temp_dir() . '/studygo-admob-ssv-keys.json';
        if (!$force && is_file($cache) && time() - (int)filemtime($cache) < self::CACHE_TTL) {
            $data = json_decode((string)file_get_contents($cache), true);
            if (is_array($data)) return $data;
        }
        if (!function_exists('curl_init')) throw new \RuntimeException('php_curl_extension_required_for_admob_ssv');
        $ch = curl_init(self::KEY_URL);
        curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER=>true,CURLOPT_FOLLOWLOCATION=>false,CURLOPT_CONNECTTIMEOUT=>5,CURLOPT_TIMEOUT=>10,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2,CURLOPT_HTTPHEADER=>['Accept: application/json']]);
        $raw = curl_exec($ch); $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE); curl_close($ch);
        if (!is_string($raw) || $status !== 200) throw new \RuntimeException('admob_public_keys_unavailable');
        $json = json_decode($raw, true);
        if (!is_array($json['keys'] ?? null)) throw new \RuntimeException('invalid_admob_public_keys_response');
        $keys = [];
        foreach ($json['keys'] as $key) if (isset($key['keyId'],$key['pem']) && is_string($key['pem'])) $keys[(string)$key['keyId']] = $key['pem'];
        if (!$keys) throw new \RuntimeException('empty_admob_public_keys');
        @file_put_contents($cache, json_encode($keys, JSON_THROW_ON_ERROR), LOCK_EX);
        return $keys;
    }
}
