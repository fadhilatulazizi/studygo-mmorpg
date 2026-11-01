<?php
declare(strict_types=1);

namespace StudyGo\Education;

use PDO;

final class EducationApi
{
    public function __construct(private PDO $pdo, private array $config) {}

    public function handle(string $method, string $path, array $body, int $userId): ?array
    {
        if ($method === 'GET' && $path === '/api/v1/materials') return ['status'=>200,'data'=>['materials'=>$this->materials($userId)]];
        if ($method === 'POST' && $path === '/api/v1/materials') return ['status'=>201,'data'=>['material'=>$this->uploadMaterial($userId,$body)]];
        if ($method === 'GET' && $path === '/api/v1/reminders') return ['status'=>200,'data'=>['reminders'=>$this->reminders($userId)]];
        if ($method === 'POST' && $path === '/api/v1/reminders') return ['status'=>201,'data'=>['reminder'=>$this->createReminder($userId,$body)]];
        if ($method === 'GET' && $path === '/api/v1/notifications') return ['status'=>200,'data'=>['notifications'=>$this->notifications($userId)]];
        if ($method === 'POST' && preg_match('#^/api/v1/notifications/(\\d+)/read$#',$path,$nm)) { $this->markNotificationRead($userId,(int)$nm[1]); return ['status'=>200,'data'=>['read'=>true]]; }
        if ($method === 'GET' && $path === '/api/v1/subjects') return ['status'=>200,'data'=>['subjects'=>$this->subjects()]];
        if ($method === 'GET' && $path === '/api/v1/planner/tasks') return ['status'=>200,'data'=>['tasks'=>$this->tasks($userId)]];
        if ($method === 'POST' && $path === '/api/v1/planner/tasks') return ['status'=>201,'data'=>['task'=>$this->createTask($userId,$body)]];
        if (preg_match('#^/api/v1/planner/tasks/(\d+)$#',$path,$m)) {
            if ($method === 'PATCH') return ['status'=>200,'data'=>['task'=>$this->updateTask($userId,(int)$m[1],$body)]];
            if ($method === 'DELETE') { $this->deleteTask($userId,(int)$m[1]); return ['status'=>200,'data'=>['deleted'=>true]]; }
        }
        if ($method === 'GET' && $path === '/api/v1/notes') return ['status'=>200,'data'=>['notes'=>$this->notes($userId)]];
        if ($method === 'POST' && $path === '/api/v1/notes') return ['status'=>201,'data'=>['note'=>$this->createNote($userId,$body)]];
        if (preg_match('#^/api/v1/notes/(\d+)$#',$path,$m)) {
            if ($method === 'PATCH') return ['status'=>200,'data'=>['note'=>$this->updateNote($userId,(int)$m[1],$body)]];
            if ($method === 'DELETE') { $this->deleteNote($userId,(int)$m[1]); return ['status'=>200,'data'=>['deleted'=>true]]; }
        }
        if ($method === 'POST' && $path === '/api/v1/ai/solve-image') return ['status'=>200,'data'=>['answer'=>$this->solveImage($userId,$body)]];
        if ($method === 'GET' && $path === '/api/v1/ai/quota') return ['status'=>200,'data'=>$this->quota($userId)];
        if ($method === 'POST' && $path === '/api/v1/ai/tutor') return ['status'=>200,'data'=>['answer'=>$this->askTutor($userId,$body)]];
        return null;
    }

    public function rewardCallback(array $b, string $signature): array
    {
        $secret=(string)($this->config['ads']['callback_secret']??'');
        if (strlen($secret)<32 || $signature==='') throw new \RuntimeException('reward_callback_not_configured');
        $raw=json_encode($b,JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR);
        $expected=hash_hmac('sha256',$raw,$secret);
        if (!hash_equals($expected,$signature)) throw new \RuntimeException('invalid_reward_signature');
        $userId=(int)($b['userId']??0); $transactionId=trim((string)($b['transactionId']??'')); $provider=(string)($b['provider']??'admob');
        if($userId<=0 || $transactionId==='' || strlen($transactionId)>190) throw new \InvalidArgumentException('invalid_reward_payload');
        $this->pdo->beginTransaction();
        try {
            $q=$this->pdo->prepare("SELECT questions_used,reward_ads_used FROM study_ai_daily_usage WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR)) FOR UPDATE");
            $q->execute([$userId]); $row=$q->fetch();
            if(!$row) { $this->pdo->prepare("INSERT INTO study_ai_daily_usage(user_id,usage_date) VALUES(?,DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR)))")->execute([$userId]); $row=['questions_used'=>0,'reward_ads_used'=>0]; }
            if((int)$row['reward_ads_used']>=3) throw new \DomainException('daily_reward_limit_reached');
            $ins=$this->pdo->prepare("INSERT INTO study_ad_reward_events(provider,transaction_id,user_id,reward_amount) VALUES(?,?,?,3)");
            $ins->execute([$provider,$transactionId,$userId]);
            $this->pdo->prepare("UPDATE study_ai_daily_usage SET rewarded_questions=rewarded_questions+3,reward_ads_used=reward_ads_used+1 WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR))")->execute([$userId]);
            $this->pdo->commit();
            return $this->quota($userId);
        } catch (\Throwable $e) { if($this->pdo->inTransaction()) $this->pdo->rollBack(); throw $e; }
    }

    private function materials(int $u): array
    {
        $q=$this->pdo->prepare("SELECT id,subject_id,title,description,original_name,mime_type,file_size,material_type,created_at FROM study_materials WHERE user_id=? ORDER BY created_at DESC LIMIT 200");$q->execute([$u]);return $q->fetchAll();
    }
    private function uploadMaterial(int $u,array $b): array
    {
        if(!isset($_FILES['file'])||$_FILES['file']['error']!==UPLOAD_ERR_OK)throw new \InvalidArgumentException('material_file_required');
        $file=$_FILES['file'];$max=(int)($this->config['uploads']['max_bytes']??52428800);
        if($file['size']<1||$file['size']>$max)throw new \InvalidArgumentException('material_file_size_invalid');
        $finfo=new \finfo(FILEINFO_MIME_TYPE);$mime=$finfo->file($file['tmp_name']);
        $allowed=['application/pdf'=>'pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document'=>'docx','application/vnd.openxmlformats-officedocument.presentationml.presentation'=>'pptx','video/mp4'=>'video','video/webm'=>'video','image/jpeg'=>'image','image/png'=>'image','image/webp'=>'image'];
        if(!isset($allowed[$mime]))throw new \InvalidArgumentException('unsupported_material_type');
        $dir=(string)($this->config['uploads']['directory']??(sys_get_temp_dir().'/studygo-uploads'));
        if(!is_dir($dir)&&!mkdir($dir,0700,true)&&!is_dir($dir))throw new \RuntimeException('upload_storage_unavailable');
        $stored=bin2hex(random_bytes(24));$target=rtrim($dir,DIRECTORY_SEPARATOR).DIRECTORY_SEPARATOR.$stored;
        if(!move_uploaded_file($file['tmp_name'],$target))throw new \RuntimeException('upload_move_failed');
        chmod($target,0600);
        $title=trim((string)($b['title']??pathinfo($file['name'],PATHINFO_FILENAME)));if($title===''||mb_strlen($title)>180){@unlink($target);throw new \InvalidArgumentException('invalid_material_title');}
        $q=$this->pdo->prepare("INSERT INTO study_materials(user_id,subject_id,title,description,original_name,storage_name,mime_type,file_size,material_type) VALUES(?,?,?,?,?,?,?,?,?)");
        $q->execute([$u,$this->nullableInt($b['subjectId']??null),$title,$this->limitText($b['description']??null,2000),basename((string)$file['name']),$stored,$mime,(int)$file['size'],$allowed[$mime]]);
        return ['id'=>(int)$this->pdo->lastInsertId(),'title'=>$title,'originalName'=>basename((string)$file['name']),'mimeType'=>$mime,'size'=>(int)$file['size'],'type'=>$allowed[$mime]];
    }
    private function reminders(int $u): array
    {
        $q=$this->pdo->prepare("SELECT id,task_id,title,message,remind_at,status,created_at FROM study_reminders WHERE user_id=? ORDER BY remind_at LIMIT 200");$q->execute([$u]);return $q->fetchAll();
    }
    private function createReminder(int $u,array $b): array
    {
        $title=trim((string)($b['title']??''));if($title===''||mb_strlen($title)>180)throw new \InvalidArgumentException('invalid_reminder_title');
        $at=$this->dateOrNull($b['remindAt']??null);if($at===null)throw new \InvalidArgumentException('remind_at_required');
        $task=$this->nullableInt($b['taskId']??null);
        $q=$this->pdo->prepare("INSERT INTO study_reminders(user_id,task_id,title,message,remind_at) VALUES(?,?,?,?,?)");$q->execute([$u,$task,$title,$this->limitText($b['message']??null,1000),$at]);
        $id=(int)$this->pdo->lastInsertId();return ['id'=>$id,'title'=>$title,'remindAt'=>$at,'status'=>'pending'];
    }
    private function notifications(int $u): array
    {
        $q=$this->pdo->prepare("SELECT id,title,body,notification_type,data_json,read_at,created_at FROM study_notifications WHERE user_id=? ORDER BY created_at DESC LIMIT 100");$q->execute([$u]);return $q->fetchAll();
    }
    private function markNotificationRead(int $u,int $id): void
    {
        $q=$this->pdo->prepare("UPDATE study_notifications SET read_at=UTC_TIMESTAMP() WHERE id=? AND user_id=?");$q->execute([$id,$u]);if(!$q->rowCount())throw new \InvalidArgumentException('notification_not_found');
    }

    private function subjects(): array {
        return $this->pdo->query("SELECT id,code,name,description,icon FROM study_subjects WHERE is_active=1 ORDER BY sort_order,name")->fetchAll();
    }
    private function tasks(int $u): array {
        $q=$this->pdo->prepare("SELECT id,subject_id,title,description,due_at,priority,status,reminder_at,created_at,updated_at FROM study_tasks WHERE user_id=? ORDER BY (due_at IS NULL),due_at LIMIT 200");
        $q->execute([$u]); return $q->fetchAll();
    }
    private function createTask(int $u,array $b): array {
        $title=trim((string)($b['title']??'')); if($title===''||mb_strlen($title)>180) throw new \InvalidArgumentException('invalid_title');
        $subject=$this->nullableInt($b['subjectId']??null); $due=$this->dateOrNull($b['dueAt']??null); $rem=$this->dateOrNull($b['reminderAt']??null);
        $priority=$this->enum($b['priority']??'normal',['low','normal','high']); $status=$this->enum($b['status']??'todo',['todo','in_progress','done','cancelled']);
        $q=$this->pdo->prepare("INSERT INTO study_tasks(user_id,subject_id,title,description,due_at,priority,status,reminder_at) VALUES(?,?,?,?,?,?,?,?)");
        $q->execute([$u,$subject,$title,$this->limitText($b['description']??null,10000),$due,$priority,$status,$rem]);
        return $this->getTask($u,(int)$this->pdo->lastInsertId());
    }
    private function updateTask(int $u,int $id,array $b): array {
        $current=$this->getTask($u,$id);
        $title=trim((string)($b['title']??$current['title'])); if($title===''||mb_strlen($title)>180) throw new \InvalidArgumentException('invalid_title');
        $status=$this->enum($b['status']??$current['status'],['todo','in_progress','done','cancelled']);
        $priority=$this->enum($b['priority']??$current['priority'],['low','normal','high']);
        $desc=array_key_exists('description',$b)?$this->limitText($b['description'],10000):$current['description'];
        $due=array_key_exists('dueAt',$b)?$this->dateOrNull($b['dueAt']):$current['due_at'];
        $sub=array_key_exists('subjectId',$b)?$this->nullableInt($b['subjectId']):$current['subject_id'];
        $rem=array_key_exists('reminderAt',$b)?$this->dateOrNull($b['reminderAt']):$current['reminder_at'];
        $q=$this->pdo->prepare("UPDATE study_tasks SET title=?,description=?,due_at=?,priority=?,status=?,subject_id=?,reminder_at=? WHERE id=? AND user_id=?");
        $q->execute([$title,$desc,$due,$priority,$status,$sub,$rem,$id,$u]); return $this->getTask($u,$id);
    }
    private function getTask(int $u,int $id): array { $q=$this->pdo->prepare("SELECT id,subject_id,title,description,due_at,priority,status,reminder_at,created_at,updated_at FROM study_tasks WHERE id=? AND user_id=?");$q->execute([$id,$u]);$r=$q->fetch();if(!$r)throw new \InvalidArgumentException('task_not_found');return $r; }
    private function deleteTask(int $u,int $id): void {$q=$this->pdo->prepare("DELETE FROM study_tasks WHERE id=? AND user_id=?");$q->execute([$id,$u]);if(!$q->rowCount())throw new \InvalidArgumentException('task_not_found');}
    private function notes(int $u): array {$q=$this->pdo->prepare("SELECT id,subject_id,title,content,created_at,updated_at FROM study_notes WHERE user_id=? ORDER BY updated_at DESC LIMIT 200");$q->execute([$u]);return $q->fetchAll();}
    private function createNote(int $u,array $b): array {$title=trim((string)($b['title']??''));$content=(string)($b['content']??'');if($title===''||mb_strlen($title)>180||$content===''||mb_strlen($content)>100000)throw new \InvalidArgumentException('invalid_note');$q=$this->pdo->prepare("INSERT INTO study_notes(user_id,subject_id,title,content) VALUES(?,?,?,?)");$q->execute([$u,$this->nullableInt($b['subjectId']??null),$title,$content]);return $this->getNote($u,(int)$this->pdo->lastInsertId());}
    private function updateNote(int $u,int $id,array $b): array {$old=$this->getNote($u,$id);$title=trim((string)($b['title']??$old['title']));$content=(string)($b['content']??$old['content']);if($title===''||mb_strlen($title)>180||$content===''||mb_strlen($content)>100000)throw new \InvalidArgumentException('invalid_note');$sub=array_key_exists('subjectId',$b)?$this->nullableInt($b['subjectId']):$old['subject_id'];$q=$this->pdo->prepare("UPDATE study_notes SET title=?,content=?,subject_id=? WHERE id=? AND user_id=?");$q->execute([$title,$content,$sub,$id,$u]);return $this->getNote($u,$id);}
    private function getNote(int $u,int $id): array {$q=$this->pdo->prepare("SELECT id,subject_id,title,content,created_at,updated_at FROM study_notes WHERE id=? AND user_id=?");$q->execute([$id,$u]);$r=$q->fetch();if(!$r)throw new \InvalidArgumentException('note_not_found');return $r;}
    private function deleteNote(int $u,int $id): void {$q=$this->pdo->prepare("DELETE FROM study_notes WHERE id=? AND user_id=?");$q->execute([$id,$u]);if(!$q->rowCount())throw new \InvalidArgumentException('note_not_found');}
    private function quota(int $u): array {$q=$this->pdo->prepare("SELECT questions_used,rewarded_questions,reward_ads_used FROM study_ai_daily_usage WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR))");$q->execute([$u]);$r=$q->fetch()?:['questions_used'=>0,'rewarded_questions'=>0,'reward_ads_used'=>0];$limit=5+(int)$r['rewarded_questions'];return ['date'=>(new \DateTimeImmutable('now',new \DateTimeZone('Asia/Jakarta')))->format('Y-m-d'),'timezone'=>'Asia/Jakarta','freeLimit'=>5,'bonusQuestions'=>(int)$r['rewarded_questions'],'rewardAdsUsed'=>(int)$r['reward_ads_used'],'rewardAdsRemaining'=>max(0,3-(int)$r['reward_ads_used']),'questionsUsed'=>(int)$r['questions_used'],'questionsRemaining'=>max(0,$limit-(int)$r['questions_used']),'dailyMaximum'=>14];}

    private function askTutor(int $u,array $b): string {
        $prompt=trim((string)($b['question']??''));if($prompt===''||mb_strlen($prompt)>12000)throw new \InvalidArgumentException('invalid_question');
        $requestId=(string)($b['requestId']??'');if(!preg_match('/^[0-9a-fA-F-]{36}$/',$requestId))throw new \InvalidArgumentException('valid_request_id_required');
        $this->pdo->beginTransaction();
        try {
            $this->pdo->prepare("INSERT IGNORE INTO study_ai_daily_usage(user_id,usage_date) VALUES(?,DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR)))")->execute([$u]);
            $q=$this->pdo->prepare("SELECT questions_used,rewarded_questions FROM study_ai_daily_usage WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR)) FOR UPDATE");$q->execute([$u]);$usage=$q->fetch();
            if((int)$usage['questions_used'] >= 5+(int)$usage['rewarded_questions'])throw new \DomainException('daily_ai_quota_exceeded');
            $dup=$this->pdo->prepare("SELECT id FROM study_ai_requests WHERE user_id=? AND request_id=?");$dup->execute([$u,$requestId]);if($dup->fetch())throw new \DomainException('duplicate_request_id');
            $this->pdo->prepare("UPDATE study_ai_daily_usage SET questions_used=questions_used+1 WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR))")->execute([$u]);
            $provider=(string)($this->config['ai']['provider']??'gemini');$model=(string)($this->config['ai']['model']??'gemini-2.5-flash');
            $this->pdo->prepare("INSERT INTO study_ai_requests(user_id,request_id,provider,model,prompt_hash) VALUES(?,?,?,?,?)")->execute([$u,$requestId,$provider,$model,hash('sha256',$prompt)]);
            $this->pdo->commit();
        } catch (\Throwable $e) {if($this->pdo->inTransaction())$this->pdo->rollBack();throw $e;}
        try { return $this->callProvider($prompt); }
        catch (\Throwable $e) {
            $this->pdo->prepare("UPDATE study_ai_daily_usage SET questions_used=GREATEST(questions_used-1,0) WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR))")->execute([$u]);
            $this->pdo->prepare("DELETE FROM study_ai_requests WHERE user_id=? AND request_id=?")->execute([$u,$requestId]);
            throw $e;
        }
    }
    private function solveImage(int $u,array $b): string
    {
        $mime=(string)($b['mimeType']??'');$data=(string)($b['imageBase64']??'');
        if(!in_array($mime,['image/jpeg','image/png','image/webp'],true)||$data===''||strlen($data)>11000000)throw new \InvalidArgumentException('invalid_image_payload');
        $binary=base64_decode($data,true);if($binary===false||strlen($binary)>8000000)throw new \InvalidArgumentException('image_too_large_or_invalid');
        $finfo=new \finfo(FILEINFO_MIME_TYPE);if($finfo->buffer($binary)!==$mime)throw new \InvalidArgumentException('image_mime_mismatch');
        $prompt=trim((string)($b['question']??'Bacalah soal pada gambar dan jelaskan cara menyelesaikannya langkah demi langkah.'));
        if(mb_strlen($prompt)>3000)throw new \InvalidArgumentException('question_too_long');
        $requestId=(string)($b['requestId']??'');if(!preg_match('/^[0-9a-fA-F-]{36}$/',$requestId))throw new \InvalidArgumentException('valid_request_id_required');
        $this->pdo->beginTransaction();
        try{
            $this->pdo->prepare("INSERT IGNORE INTO study_ai_daily_usage(user_id,usage_date) VALUES(?,DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR)))")->execute([$u]);
            $q=$this->pdo->prepare("SELECT questions_used,rewarded_questions FROM study_ai_daily_usage WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR)) FOR UPDATE");$q->execute([$u]);$usage=$q->fetch();
            if((int)$usage['questions_used']>=5+(int)$usage['rewarded_questions'])throw new \DomainException('daily_ai_quota_exceeded');
            $this->pdo->prepare("UPDATE study_ai_daily_usage SET questions_used=questions_used+1 WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR))")->execute([$u]);
            $provider=(string)($this->config['ai']['provider']??'gemini');$model=(string)($this->config['ai']['model']??'gemini-2.5-flash');
            $this->pdo->prepare("INSERT INTO study_ai_requests(user_id,request_id,provider,model,prompt_hash) VALUES(?,?,?,?,?)")->execute([$u,$requestId,$provider,$model,hash('sha256',$prompt.'|'.hash('sha256',$binary))]);
            $this->pdo->commit();
        }catch(\Throwable $e){if($this->pdo->inTransaction())$this->pdo->rollBack();throw $e;}
        try{return $this->callImageProvider($prompt,$mime,$data);}
        catch(\Throwable $e){$this->pdo->prepare("UPDATE study_ai_daily_usage SET questions_used=GREATEST(questions_used-1,0) WHERE user_id=? AND usage_date=DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 HOUR))")->execute([$u]);$this->pdo->prepare("DELETE FROM study_ai_requests WHERE user_id=? AND request_id=?")->execute([$u,$requestId]);throw $e;}
    }
    private function callImageProvider(string $prompt,string $mime,string $base64): string
    {
        if(!function_exists('curl_init'))throw new \RuntimeException('php_curl_extension_required');
        $provider=(string)($this->config['ai']['provider']??'gemini');$model=(string)($this->config['ai']['model']??'gemini-2.5-flash');
        $system='Anda adalah StudyGo AI Tutor. Baca gambar soal dengan teliti, tulis informasi yang diketahui, jelaskan langkah penyelesaian, dan berikan jawaban akhir. Jika gambar tidak terbaca, minta pengguna mengirim ulang.';
        if($provider==='openai'){
            $key=(string)($this->config['ai']['openai_api_key']??'');if($key==='')throw new \RuntimeException('ai_provider_not_configured');
            $url='https://api.openai.com/v1/responses';$payload=['model'=>$model,'input'=>[['role'=>'system','content'=>$system],['role'=>'user','content'=>[['type'=>'input_text','text'=>$prompt],['type'=>'input_image','image_url'=>'data:'.$mime.';base64,'.$base64]]]]];$headers=['Authorization: Bearer '.$key,'Content-Type: application/json'];
        }else{
            $key=(string)($this->config['ai']['gemini_api_key']??'');if($key==='')throw new \RuntimeException('ai_provider_not_configured');
            $url='https://generativelanguage.googleapis.com/v1beta/models/'.rawurlencode($model).':generateContent?key='.rawurlencode($key);
            $payload=['systemInstruction'=>['parts'=>[['text'=>$system]]],'contents'=>[['role'=>'user','parts'=>[['text'=>$prompt],['inlineData'=>['mimeType'=>$mime,'data'=>$base64]]]]],'generationConfig'=>['temperature'=>0.3,'maxOutputTokens'=>2048]];$headers=['Content-Type: application/json'];
        }
        $ch=curl_init($url);curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_RETURNTRANSFER=>true,CURLOPT_HTTPHEADER=>$headers,CURLOPT_POSTFIELDS=>json_encode($payload,JSON_THROW_ON_ERROR),CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_TIMEOUT=>60]);
        $raw=curl_exec($ch);$code=(int)curl_getinfo($ch,CURLINFO_HTTP_CODE);$err=curl_error($ch);curl_close($ch);
        if($raw===false||$code<200||$code>=300){error_log('StudyGo image AI provider HTTP '.$code.' '.$err);throw new \RuntimeException('ai_service_unavailable');}
        $d=json_decode($raw,true);$answer=$provider==='openai'?($d['output'][0]['content'][0]['text']??null):($d['candidates'][0]['content']['parts'][0]['text']??null);
        if(!is_string($answer)||$answer==='')throw new \RuntimeException('ai_empty_response');return $answer;
    }

    private function callProvider(string $prompt): string {
        if(!function_exists('curl_init'))throw new \RuntimeException('php_curl_extension_required');
        $provider=(string)($this->config['ai']['provider']??'gemini');$model=(string)($this->config['ai']['model']??'gemini-2.5-flash');
        if($provider==='openai') {
            $key=(string)($this->config['ai']['openai_api_key']??'');if($key==='')throw new \RuntimeException('ai_provider_not_configured');
            $url='https://api.openai.com/v1/responses';$payload=['model'=>$model,'input'=>[['role'=>'system','content'=>'Anda adalah StudyGo AI, tutor pendidikan yang ramah, akurat, dan menjelaskan langkah demi langkah sesuai tingkat pelajar. Jika tidak yakin, katakan.'],['role'=>'user','content'=>$prompt]]];
            $headers=['Authorization: Bearer '.$key,'Content-Type: application/json'];
        } else {
            $key=(string)($this->config['ai']['gemini_api_key']??'');if($key==='')throw new \RuntimeException('ai_provider_not_configured');
            $url='https://generativelanguage.googleapis.com/v1beta/models/'.rawurlencode($model).':generateContent?key='.rawurlencode($key);
            $payload=['systemInstruction'=>['parts'=>[['text'=>'Anda adalah StudyGo AI, tutor pendidikan yang ramah, akurat, dan menjelaskan langkah demi langkah sesuai tingkat pelajar. Jika tidak yakin, katakan.']]],'contents'=>[['role'=>'user','parts'=>[['text'=>$prompt]]]],'generationConfig'=>['temperature'=>0.4,'maxOutputTokens'=>2048]];
            $headers=['Content-Type: application/json'];
        }
        $ch=curl_init($url);curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_RETURNTRANSFER=>true,CURLOPT_HTTPHEADER=>$headers,CURLOPT_POSTFIELDS=>json_encode($payload,JSON_THROW_ON_ERROR),CURLOPT_CONNECTTIMEOUT=>10,CURLOPT_TIMEOUT=>45]);
        $raw=curl_exec($ch);$code=(int)curl_getinfo($ch,CURLINFO_HTTP_CODE);$err=curl_error($ch);curl_close($ch);
        if($raw===false||$code<200||$code>=300){error_log('StudyGo AI provider error HTTP '.$code.' '.$err);throw new \RuntimeException('ai_service_unavailable');}
        $data=json_decode($raw,true);$text=$provider==='openai'?($data['output'][0]['content'][0]['text']??null):($data['candidates'][0]['content']['parts'][0]['text']??null);
        if(!is_string($text)||$text==='')throw new \RuntimeException('ai_empty_response');return $text;
    }
    private function nullableInt(mixed $v): ?int {if($v===null||$v==='')return null;$n=filter_var($v,FILTER_VALIDATE_INT);if($n===false||$n<=0)throw new \InvalidArgumentException('invalid_subject_id');return $n;}
    private function dateOrNull(mixed $v): ?string {if($v===null||$v==='')return null;try{$d=new \DateTimeImmutable((string)$v,new \DateTimeZone('UTC'));return $d->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d H:i:s');}catch(\Throwable){throw new \InvalidArgumentException('invalid_datetime');}}
    private function enum(mixed $v,array $allowed): string {$s=(string)$v;if(!in_array($s,$allowed,true))throw new \InvalidArgumentException('invalid_enum_value');return $s;}
    private function limitText(mixed $v,int $max): ?string {if($v===null)return null;$s=trim((string)$v);if(mb_strlen($s)>$max)throw new \InvalidArgumentException('text_too_long');return $s;}
}
