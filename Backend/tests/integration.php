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
 spl_autoload_register(static function(string $class):void{$prefix='StudyGo\\';if(!str_starts_with($class,$prefix))return;$file=dirname(__DIR__).'/src/'.str_replace('\\','/',substr($class,strlen($prefix))).'.php';if(is_file($file))require $file;});
 $api=new StudyGo\Education\EducationApi($pdo,['ai'=>['provider'=>'gemini','model'=>'gemini-test']]);
 $taskResult=$api->handle('POST','/api/v1/planner/tasks',['title'=>'API integration task','priority'=>'high'],$uid);
 if(($taskResult['status']??0)!==201||empty($taskResult['data']['task']['id']))throw new RuntimeException('Education task API integration failed');
 $listResult=$api->handle('GET','/api/v1/planner/tasks',[],$uid);
 if(count($listResult['data']['tasks']??[])<2)throw new RuntimeException('Education task list API integration failed');
 $noteResult=$api->handle('POST','/api/v1/notes',['title'=>'API integration note','content'=>'hello'],$uid);
 if(($noteResult['status']??0)!==201)throw new RuntimeException('Education note API integration failed');
 $reminderResult=$api->handle('POST','/api/v1/reminders',['title'=>'API integration reminder','remindAt'=>gmdate('Y-m-d\\TH:i:s\\Z',time()+3600)],$uid);
 if(($reminderResult['status']??0)!==201)throw new RuntimeException('Education reminder API integration failed');
 $quota=$api->handle('GET','/api/v1/ai/quota',[],$uid);
 if(($quota['data']['dailyMaximum']??0)!==14||($quota['data']['timezone']??'')!=='Asia/Jakarta')throw new RuntimeException('AI quota API integration failed');
 $pdo->rollBack();
 echo "Database integration checks passed.\n";
}catch(Throwable $e){if($pdo->inTransaction())$pdo->rollBack();throw $e;}
