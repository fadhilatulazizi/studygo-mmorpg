<?php
declare(strict_types=1);

$dsn=getenv('TEST_DB_DSN')?:'mysql:host=127.0.0.1;dbname=studygo_test;charset=utf8mb4';
$pdo=new PDO($dsn,getenv('TEST_DB_USER')?:'root',getenv('TEST_DB_PASSWORD')?:'',[
 PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC
]);
$required=['studygo_users','studygo_refresh_tokens','studygo_email_tokens','studygo_login_throttles','study_subjects','study_tasks','study_notes','study_ai_daily_usage','study_ai_requests','study_materials','study_reminders','study_notifications','studygo_admin_users','studygo_admin_settings','study_admob_ssv_events'];
foreach($required as $table){$q=$pdo->prepare("SHOW TABLES LIKE ?");$q->execute([$table]);if(!$q->fetchColumn())throw new RuntimeException("Missing table: ".$table);}
$pdo->beginTransaction();
try{
 $email='ci+'.bin2hex(random_bytes(5)).'@example.test';
 $pdo->prepare("INSERT INTO studygo_users(email,password_hash,display_name) VALUES(?,?,?)")->execute([$email,password_hash('Integration-Test-Password',PASSWORD_DEFAULT),'CI Student']);
 $uid=(int)$pdo->lastInsertId();
 $pdo->prepare("INSERT INTO studygo_email_tokens(user_id,token_hash,purpose,expires_at) VALUES(?,?,'verify_email',DATE_ADD(UTC_TIMESTAMP(),INTERVAL 1 DAY))")->execute([$uid,hash('sha256',random_bytes(32))]);
 $pdo->prepare("INSERT INTO studygo_refresh_tokens(user_id,token_hash,token_type,session_id,expires_at) VALUES(?,?,'refresh',?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL 1 DAY))")->execute([$uid,hash('sha256',random_bytes(32)),sprintf('%08x-0000-4000-8000-000000000000',$uid)]);
 $pdo->prepare("INSERT INTO study_ai_daily_usage(user_id,usage_date) VALUES(?,DATE(DATE_ADD(UTC_TIMESTAMP(),INTERVAL 7 HOUR)))")->execute([$uid]);
 $pdo->prepare("INSERT INTO study_tasks(user_id,title) VALUES(?,?)")->execute([$uid,'Integration test task']);
 $pdo->prepare("INSERT INTO study_notes(user_id,title,content) VALUES(?,?,?)")->execute([$uid,'CI note','test content']);
 $pdo->prepare("INSERT INTO study_reminders(user_id,title,remind_at) VALUES(?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL 1 DAY))")->execute([$uid,'CI reminder']);
 $pdo->prepare("INSERT INTO study_notifications(user_id,title,body) VALUES(?,?,?)")->execute([$uid,'CI notification','integration']);
 $pdo->rollBack();
 echo "Database integration checks passed.\n";
}catch(Throwable $e){if($pdo->inTransaction())$pdo->rollBack();throw $e;}
