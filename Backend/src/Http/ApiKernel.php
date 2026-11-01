<?php
declare(strict_types=1);

namespace StudyGo\Http;

use PDO;
use StudyGo\Education\EducationApi;
use StudyGo\Security\GameJwtIssuer;
use StudyGo\Ads\AdMobSsvVerifier;

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
            header('Access-Control-Allow-Origin: '.$origin);
            header('Vary: Origin');
            header('Access-Control-Allow-Headers: Content-Type, Authorization, X-StudyGo-Signature');
            header('Access-Control-Allow-Methods: GET, POST, PATCH, PUT, DELETE, OPTIONS');
        }
        if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') { http_response_code(204); return; }

        try {
            $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
            $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
            $body = $this->jsonBody();

            if ($method === 'GET' && $path === '/health') {
                $this->respond(200, ['status'=>'ok','service'=>'studygo-api']);
                return;
            }
            if ($method === 'POST' && $path === '/api/v1/auth/register') { $this->register($body); return; }
            if ($method === 'POST' && $path === '/api/v1/auth/login') { $this->login($body); return; }
            if ($method === 'POST' && $path === '/api/v1/auth/refresh') { $this->refresh($body); return; }
            if ($method === 'POST' && $path === '/api/v1/auth/logout') { $this->logout($body); return; }
            if ($method === 'GET' && $path === '/api/v1/auth/me') {
                $u=$this->authenticatedUser();
                $this->respond(200,['user'=>['id'=>(int)$u['id'],'email'=>$u['email'],'displayName'=>$u['display_name']]]);
                return;
            }
            if ($method === 'POST' && $path === '/api/v1/game/token') { $this->gameToken($body); return; }
            if ($method === 'GET' && $path === '/internal/ads/admob-ssv') {
                $this->admobSsv(); return;
            }
            if ($method === 'POST' && $path === '/internal/ads/reward-callback') {
                $education=new EducationApi($this->pdo,$this->config);
                $result=$education->rewardCallback($body,(string)($_SERVER['HTTP_X_STUDYGO_SIGNATURE']??''));
                $this->respond(200,$result); return;
            }

            $user=$this->authenticatedUser();
            $education=new EducationApi($this->pdo,$this->config);
            $result=$education->handle($method,$path,$body,(int)$user['id']);
            if($result!==null){$this->respond($result['status'],$result['data']);return;}
            $this->respond(404,['error'=>'not_found']);
        } catch (\DomainException $e) {
            $status=in_array($e->getMessage(),['daily_ai_quota_exceeded','daily_reward_limit_reached'],true)?429:409;
            $this->respond($status,['error'=>$e->getMessage()]);
        } catch (\InvalidArgumentException $e) {
            $this->respond(422,['error'=>$e->getMessage()]);
        } catch (\PDOException $e) {
            if($e->getCode()==='23000')$this->respond(409,['error'=>'conflict']);
            else{error_log($e->getMessage());$this->respond(500,['error'=>'internal_error']);}
        } catch (\Throwable $e) {
            error_log($e->getMessage());$this->respond(500,['error'=>$e->getMessage()==='ai_service_unavailable'?'ai_service_unavailable':'internal_error']);
        }
    }

    private function register(array $b): void
    {
        $email=strtolower(trim((string)($b['email']??'')));
        $password=(string)($b['password']??'');
        $name=trim((string)($b['displayName']??''));
        if(!filter_var($email,FILTER_VALIDATE_EMAIL)||strlen($email)>190)throw new \InvalidArgumentException('invalid_email');
        if(strlen($password)<10||strlen($password)>200)throw new \InvalidArgumentException('password_must_be_10_to_200_characters');
        if($name===''||mb_strlen($name)>80)throw new \InvalidArgumentException('invalid_display_name');
        $this->pdo->beginTransaction();
        try{
            $q=$this->pdo->prepare("INSERT INTO studygo_users(email,password_hash,display_name) VALUES(?,?,?)");
            $q->execute([$email,password_hash($password,PASSWORD_DEFAULT),$name]);
            $id=(int)$this->pdo->lastInsertId();
            $this->pdo->prepare("INSERT INTO game_players(studygo_user_id,display_name) VALUES(?,?)")->execute([$id,$name]);
            $this->pdo->commit();
        }catch(\Throwable $e){if($this->pdo->inTransaction())$this->pdo->rollBack();throw $e;}
        $this->respond(201,['user'=>['id'=>$id,'email'=>$email,'displayName'=>$name],'message'=>'account_created_login_required']);
    }

    private function login(array $b): void
    {
        $email=strtolower(trim((string)($b['email']??'')));
        $password=(string)($b['password']??'');
        if(!filter_var($email,FILTER_VALIDATE_EMAIL)||strlen($email)>190||$password==='') {
            $this->respond(401,['error'=>'invalid_credentials']); return;
        }
        $ip=(string)($_SERVER['REMOTE_ADDR']??'unknown');
        $identity=hash('sha256',$email.'|'.$ip);
        $th=$this->pdo->prepare("SELECT failed_attempts,window_started_at,locked_until FROM studygo_login_throttles WHERE identity_hash=?");
        $th->execute([$identity]); $state=$th->fetch();
        if($state && $state['locked_until']!==null && strtotime($state['locked_until'].' UTC')>time()) {
            header('Retry-After: '.max(1,strtotime($state['locked_until'].' UTC')-time()));
            $this->respond(429,['error'=>'too_many_login_attempts']); return;
        }
        $q=$this->pdo->prepare("SELECT id,email,password_hash,display_name,account_status FROM studygo_users WHERE email=? LIMIT 1");
        $q->execute([$email]);$user=$q->fetch();
        if(!$user||!password_verify($password,$user['password_hash'])) {
            $now=time(); $windowStart=$state?strtotime($state['window_started_at'].' UTC'):0;
            $count=($state && $now-$windowStart<900)?(int)$state['failed_attempts']+1:1;
            $locked=$count>=5?gmdate('Y-m-d H:i:s',$now+900):null;
            $this->pdo->prepare("INSERT INTO studygo_login_throttles(identity_hash,failed_attempts,window_started_at,locked_until) VALUES(?,?,UTC_TIMESTAMP(),?) ON DUPLICATE KEY UPDATE failed_attempts=VALUES(failed_attempts),window_started_at=VALUES(window_started_at),locked_until=VALUES(locked_until)")
                ->execute([$identity,$count,$locked]);
            if($locked!==null){header('Retry-After: 900');$this->respond(429,['error'=>'too_many_login_attempts']);return;}
            $this->respond(401,['error'=>'invalid_credentials']);return;
        }
        if($user['account_status']!=='active'){$this->respond(403,['error'=>'account_not_active']);return;}
        $this->pdo->prepare("DELETE FROM studygo_login_throttles WHERE identity_hash=?")->execute([$identity]);
        if(password_needs_rehash($user['password_hash'],PASSWORD_DEFAULT))
            $this->pdo->prepare("UPDATE studygo_users SET password_hash=? WHERE id=?")->execute([password_hash($password,PASSWORD_DEFAULT),$user['id']]);
        $this->pdo->prepare("UPDATE studygo_users SET last_login_at=UTC_TIMESTAMP() WHERE id=?")->execute([$user['id']]);
        $this->issueSession((int)$user['id'],['id'=>(int)$user['id'],'email'=>$user['email'],'displayName'=>$user['display_name']]);
    }

    private function issueSession(int $userId,array $user): void
    {
        $access=$this->randomToken(32);$refresh=$this->randomToken(48);
        $days=max(1,min(90,(int)($this->config['auth']['refresh_ttl_days']??30)));
        $device=mb_substr(trim((string)($_SERVER['HTTP_X_DEVICE_LABEL']??'')),0,100);
        $ins=$this->pdo->prepare("INSERT INTO studygo_refresh_tokens(user_id,token_hash,token_type,device_label,expires_at) VALUES(?,?,'access',?,DATE_ADD(UTC_TIMESTAMP(), INTERVAL 15 MINUTE))");
        $ins->execute([$userId,hash('sha256',$access),$device?:null]);
        $ins=$this->pdo->prepare("INSERT INTO studygo_refresh_tokens(user_id,token_hash,token_type,device_label,expires_at) VALUES(?,?,'refresh',?,DATE_ADD(UTC_TIMESTAMP(), INTERVAL ".$days." DAY))");
        $ins->execute([$userId,hash('sha256',$refresh),$device?:null]);
        $this->respond(200,['user'=>$user,'accessToken'=>$access,'tokenType'=>'Bearer','expiresIn'=>900,'refreshToken'=>$refresh,'refreshExpiresIn'=>$days*86400]);
    }

    private function refresh(array $b): void
    {
        $token=(string)($b['refreshToken']??'');
        if(!preg_match('/^[A-Za-z0-9_-]{60,100}$/',$token)){$this->respond(401,['error'=>'invalid_refresh_token']);return;}
        $this->pdo->beginTransaction();
        try {
            $q=$this->pdo->prepare("SELECT t.id,t.user_id,t.device_label,u.id AS uid,u.email,u.display_name,u.account_status FROM studygo_refresh_tokens t JOIN studygo_users u ON u.id=t.user_id WHERE t.token_hash=? AND t.token_type='refresh' AND t.revoked_at IS NULL AND t.expires_at>UTC_TIMESTAMP() FOR UPDATE");
            $q->execute([hash('sha256',$token)]);$row=$q->fetch();
            if(!$row||$row['account_status']!=='active'){$this->pdo->rollBack();$this->respond(401,['error'=>'invalid_refresh_token']);return;}
            $this->pdo->prepare("UPDATE studygo_refresh_tokens SET revoked_at=UTC_TIMESTAMP(),last_used_at=UTC_TIMESTAMP() WHERE id=?")->execute([$row['id']]);
            $this->pdo->commit();
            $this->issueSession((int)$row['user_id'],['id'=>(int)$row['uid'],'email'=>$row['email'],'displayName'=>$row['display_name']]);
        } catch(\\Throwable $e) {if($this->pdo->inTransaction())$this->pdo->rollBack();throw $e;}
    }

    private function logout(array $b): void
    {
        $header=$_SERVER['HTTP_AUTHORIZATION']??'';
        $access=preg_match('/^Bearer\\s+([A-Za-z0-9_-]{40,100})$/i',$header,$m)?$m[1]:'';
        $refresh=(string)($b['refreshToken']??'');
        if($access!=='')$this->pdo->prepare("UPDATE studygo_refresh_tokens SET revoked_at=UTC_TIMESTAMP() WHERE token_hash=? AND token_type='access' AND revoked_at IS NULL")->execute([hash('sha256',$access)]);
        if(preg_match('/^[A-Za-z0-9_-]{60,100}$/',$refresh))$this->pdo->prepare("UPDATE studygo_refresh_tokens SET revoked_at=UTC_TIMESTAMP() WHERE token_hash=? AND token_type='refresh' AND revoked_at IS NULL")->execute([hash('sha256',$refresh)]);
        $this->respond(200,['loggedOut'=>true]);
    }

    private function authenticatedUser(): array
    {
        $header=$_SERVER['HTTP_AUTHORIZATION']??'';
        if(!preg_match('/^Bearer\s+([A-Za-z0-9_-]{40,100})$/i',$header,$m)){$this->respond(401,['error'=>'unauthorized']);exit;}
        $q=$this->pdo->prepare("SELECT u.id,u.email,u.display_name FROM studygo_refresh_tokens t JOIN studygo_users u ON u.id=t.user_id WHERE t.token_hash=? AND t.token_type='access' AND t.revoked_at IS NULL AND t.expires_at>UTC_TIMESTAMP() AND u.account_status='active' LIMIT 1");
        $q->execute([hash('sha256',$m[1])]);$u=$q->fetch();
        if(!$u){$this->respond(401,['error'=>'invalid_or_expired_token']);exit;}return $u;
    }

    private function gameToken(array $b): void
    {
        $u=$this->authenticatedUser();$server=trim((string)($b['serverId']??''));
        if(!preg_match('/^[A-Za-z0-9_-]{1,48}$/',$server))throw new \InvalidArgumentException('invalid_server_id');
        $q=$this->pdo->prepare("SELECT s.server_status,m.membership_status FROM game_servers s JOIN game_server_members m ON m.server_id=s.server_id WHERE s.server_id=? AND m.user_id=? LIMIT 1");
        $q->execute([$server,$u['id']]);$m=$q->fetch();
        if(!$m||$m['membership_status']!=='active'||!in_array($m['server_status'],['open','protected','transfer_locked'],true)){$this->respond(403,['error'=>'server_access_denied']);return;}
        $jwt=new GameJwtIssuer((string)($this->config['game_jwt']['secret']??''),(string)$this->config['game_jwt']['issuer'],(string)$this->config['game_jwt']['audience'],(int)$this->config['game_jwt']['ttl']);
        $this->respond(200,['token'=>$jwt->issue((int)$u['id'],$server),'tokenType'=>'Bearer','expiresIn'=>(int)$this->config['game_jwt']['ttl'],'serverId'=>$server]);
    }


    private function admobSsv(): void
    {
        if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') { $this->respond(405,['error'=>'method_not_allowed']); return; }
        $settings=$this->pdo->query("SELECT setting_key,setting_value FROM studygo_admin_settings WHERE setting_key IN ('ads.admob_ssv_enabled','ads.admob_rewarded_unit_id_android','ads.admob_rewarded_unit_id_ios','ads.admob_reward_item','ads.admob_reward_amount')")->fetchAll(PDO::FETCH_KEY_PAIR);
        if (($settings['ads.admob_ssv_enabled'] ?? '0') !== '1') { http_response_code(503); echo 'SSV disabled'; return; }
        $params=(new AdMobSsvVerifier())->verify((string)($_SERVER['QUERY_STRING'] ?? ''));
        $allowedUnits=array_filter([$settings['ads.admob_rewarded_unit_id_android']??'', $settings['ads.admob_rewarded_unit_id_ios']??'']);
        $unit=(string)$params['ad_unit'];
        $rewardItem=(string)($settings['ads.admob_reward_item']??'studygo_questions');
        $rewardAmount=(int)($settings['ads.admob_reward_amount']??3);
        $userId=filter_var($params['user_id'],FILTER_VALIDATE_INT);
        $amount=filter_var($params['reward_amount'],FILTER_VALIDATE_INT);
        $eventMs=filter_var($params['timestamp'],FILTER_VALIDATE_INT);
        $transaction=trim((string)$params['transaction_id']);
        if (!$allowedUnits || !in_array($unit,$allowedUnits,true) || $userId===false || $userId<=0 ||
            $amount===false || $amount!==$rewardAmount || (string)$params['reward_item']!==$rewardItem ||
            $eventMs===false || $transaction==='' || strlen($transaction)>190) {
            http_response_code(400); echo 'Invalid reward parameters'; return;
        }
        $nowMs=(int)floor(microtime(true)*1000);
        if ($eventMs > $nowMs+300000 || $eventMs < $nowMs-86400000) { http_response_code(400); echo 'Stale reward callback'; return; }
        $this->pdo->beginTransaction();
        try {
            $u=$this->pdo->prepare("SELECT id FROM studygo_users WHERE id=? AND account_status='active' FOR UPDATE");
            $u->execute([$userId]);
            if (!$u->fetch()) { $this->pdo->rollBack(); http_response_code(400); echo 'Unknown user'; return; }
            $this->pdo->prepare("INSERT INTO study_ai_daily_usage(user_id,usage_date) VALUES(?,DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR))) ON DUPLICATE KEY UPDATE user_id=VALUES(user_id)")->execute([$userId]);
            $q=$this->pdo->prepare("SELECT reward_ads_used FROM study_ai_daily_usage WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR)) FOR UPDATE");
            $q->execute([$userId]); $usage=$q->fetch();
            if ((int)$usage['reward_ads_used']>=3) { $this->pdo->rollBack(); http_response_code(200); echo 'Reward limit reached'; return; }
            $keyId=(int)($_GET['key_id']??0);
            $this->pdo->prepare("INSERT INTO study_admob_ssv_events(transaction_id,user_id,ad_unit,reward_item,reward_amount,event_timestamp,key_id) VALUES(?,?,?,?,?,?,?)")
                ->execute([$transaction,$userId,$unit,$rewardItem,$rewardAmount,$eventMs,$keyId]);
            $this->pdo->prepare("INSERT INTO study_ad_reward_events(provider,transaction_id,user_id,reward_amount) VALUES('admob',?,?,?)")
                ->execute([$transaction,$userId,$rewardAmount]);
            $this->pdo->prepare("UPDATE study_ai_daily_usage SET rewarded_questions=rewarded_questions+?,reward_ads_used=reward_ads_used+1 WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR))")
                ->execute([$rewardAmount,$userId]);
            $this->pdo->commit();
            http_response_code(200); echo 'OK';
        } catch (\PDOException $e) {
            if ($this->pdo->inTransaction()) $this->pdo->rollBack();
            if ($e->getCode()==='23000') { http_response_code(200); echo 'Already processed'; return; }
            throw $e;
        } catch (\Throwable $e) {
            if ($this->pdo->inTransaction()) $this->pdo->rollBack();
            throw $e;
        }
    }

    private function adminAds(string $method,array $body,int $userId): void
    {
        $role=$this->pdo->prepare("SELECT admin_role FROM studygo_admin_users WHERE user_id=?");
        $role->execute([$userId]); $adminRole=$role->fetchColumn();
        if (!$adminRole || !in_array($adminRole,['owner','admin','editor'],true)) { $this->respond(403,['error'=>'admin_access_required']); return; }
        $keys=[
            'androidAppId'=>'ads.admob_app_id_android','iosAppId'=>'ads.admob_app_id_ios',
            'androidBannerUnitId'=>'ads.admob_banner_unit_id_android','iosBannerUnitId'=>'ads.admob_banner_unit_id_ios',
            'androidRewardedUnitId'=>'ads.admob_rewarded_unit_id_android','iosRewardedUnitId'=>'ads.admob_rewarded_unit_id_ios',
            'androidInterstitialUnitId'=>'ads.admob_interstitial_unit_id_android','iosInterstitialUnitId'=>'ads.admob_interstitial_unit_id_ios',
            'rewardItem'=>'ads.admob_reward_item','rewardAmount'=>'ads.admob_reward_amount','ssvEnabled'=>'ads.admob_ssv_enabled'
        ];
        if ($method==='PUT') {
            foreach ($keys as $field=>$key) {
                if (!array_key_exists($field,$body)) continue;
                $value=$body[$field];
                if ($field==='ssvEnabled') $value=$value ? '1':'0';
                elseif ($field==='rewardAmount') { $n=filter_var($value,FILTER_VALIDATE_INT); if($n===false||$n<1||$n>100) throw new \InvalidArgumentException('invalid_reward_amount'); $value=(string)$n; }
                else { $value=trim((string)$value); if(strlen($value)>190) throw new \InvalidArgumentException('ad_setting_too_long'); }
                $this->pdo->prepare("INSERT INTO studygo_admin_settings(setting_key,setting_value,updated_by) VALUES(?,?,?) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value),updated_by=VALUES(updated_by)")
                    ->execute([$key,$value,$userId]);
            }
        }
        $q=$this->pdo->prepare("SELECT setting_key,setting_value FROM studygo_admin_settings WHERE setting_key LIKE 'ads.admob_%'");
        $q->execute(); $rows=$q->fetchAll(PDO::FETCH_KEY_PAIR);
        $result=[];
        foreach($keys as $field=>$key) $result[$field]=$rows[$key]??'';
        $result['ssvEnabled']=($result['ssvEnabled']==='1');
        $result['rewardAmount']=(int)($result['rewardAmount']?:3);
        $this->respond(200,['ads'=>$result]);
    }

    private function jsonBody(): array
    {
        $raw=file_get_contents('php://input')?:'';if($raw==='')return [];
        $v=json_decode($raw,true);if(!is_array($v))throw new \InvalidArgumentException('invalid_json_body');return $v;
    }
    private function randomToken(int $bytes): string{return rtrim(strtr(base64_encode(random_bytes($bytes)),'+/','-_'),'=');}
    private function respond(int $status,array $data): void{http_response_code($status);echo json_encode($data,JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);}
}
