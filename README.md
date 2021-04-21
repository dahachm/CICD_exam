# Отчет Exam CICD

## ___Intro___

Приложение *js_example*:

Источник: [https://github.com/dahachm/student-exam2](https://github.com/dahachm/student-exam2)

> Demonstrates how to post form data and process a JSON response using JavaScript. This allows making requests without navigating away from the page. Demonstrates using XMLHttpRequest, fetch, and jQuery.ajax. See the Flask docs about jQuery and Ajax.


Задача в этом проекте: 
1) Установить, настроить и запустить **Jenkins** (агент и мастер) с использованием docker образов
2) Написать **CI pipeline**, который:
    - клонирует файлы из репозитория с приложением и запускает python тесты 
    - собирает docker образ с ним
    - пушит это образ в приватный репозиторий на dockerhub.  
3) Написать **CD pipeline**, который:
    - использует **ansible playbook** с 3-мя ролями: **docker** (устанавливает docker на указанных хостах), **nginx** (устанавливает nginx для балансировки экземпляров приолжения `js_example`), **web** (запускает несколько docker контейнеров из ранее созданного образа с `js_example` на борту)  
    - после того, как отработает playbook и все контейнеры запущены, проверяет доступность сервера 

## 1. Dockerfile для сборки docker образа с приложением js_example внутри

Образ [dahachm/js_example:1.0](https://hub.docker.com/layers/dahachm/js_example/1.0/images/sha256-617a68f96a635b558332d1c34a55cc4e3f5b7fc2fe56ba9f444582253d2951a5?context=explore) собран на базе `python:3`. 

Для того, чтобы удалось проверить доступность приложения и успешность запуска, необходимо пробросить *порт 5000* контейнера на любой другой доступный порт хостовой ОС и запускать приложение (flask) с параметром `--host=0.0.0.0` (т.е. указать ему: "открой, пожалуйста, доступ на всех сетевых интерфейсах с IPv4 адресом").

[dockerfile:](https://github.com/dahachm/student-exam2/blob/master/Dockerfile)

```
FROM python:3

WORKDIR /usr/local/js_example

COPY . /usr/local/js_example/

ENV FLASK_APP js_example

EXPOSE 5000

RUN pip install -e .

CMD flask run --host=0.0.0.0
```

Сборка образа:

```
$ git clone https://github.com/dahachm/student-exam2.git
$ docker build -t flask:1 .
```

Запуск образа:

```
$ docker run -d -p 5000:5000 --name flask_app flask:1
```

Результат:

![Screenshot_50](https://user-images.githubusercontent.com/40645030/115621253-ec9c6f00-a2fe-11eb-9cd4-45c2f153b7e7.png)

![Screenshot_51](https://user-images.githubusercontent.com/40645030/115621262-f02ff600-a2fe-11eb-8fb7-28f4e7548edb.png)


## 2. Dockerfile для сборки образа jenkins-агента

Для того, чтобы в полной мерей выполнить следующие задания, сформировались следующие **требования к агенту**: 
  
  - установить java8, ansible, docker, git, openssh, python3 и pip3, curl
  
  - при старте контейнера считывать из (передаваемой) переменной окружения публичный ключ мастера и запускать sshd (этим занимается скрипт [setup-ssh.sh](https://github.com/dahachm/CICD_exam/blob/main/setup-ssh.sh)) 
  
Образ [dahachm/js_example:jenkins-agent-alpine](https://hub.docker.com/layers/146435311/dahachm/js_example/jenkins-agent-alpine/images/sha256-d3ac5ea62cf82572a8490d4f9b81c5c11ad7ac6b2eda5a07e919301023abf0c7?context=explore) собран на базе `alpine:3.12`. 

В нём уже установлены нужные пакеты, создан пользователь `jenkins`, внутри содержится скрипт [setup-ssh.sh](https://github.com/dahachm/CICD_exam/blob/main/setup-ssh.sh), который создает каталог */home/jenkins/.ssh*, добавляет ключ jenkins мастера, устанавливает необходимые права доступа на файлы ssh и запускает демон sshd.

Сам [dockefile](https://github.com/dahachm/CICD_exam/blob/main/jenkins-agent):

```
FROM alpine:3.12

RUN apk update \
    && apk add \
       openrc \
       openssh \
       openssh-server \
       python3 \
       py3-pip \
       openjdk8 \
       git \
       ansible \
       docker \
       curl

RUN adduser -D jenkins
 
ENV SSH_PUBLIC_KEY ''

COPY setup-ssh.sh /usr/local/setup-ssh.sh

CMD /bin/sh /usr/local/setup-ssh.sh && tail -f /dev/null
```

Сборка образа и пуш в репозиторий docker hub:

```
$ docker build -f jenkins_agent -t jenkins-agent_alpine:1 .
$ docker tag jenkins-agent_alpine:1 dahachm/js_example:jenkins-agent-alpine
$ docker push dahachm/js_example:jenkins-agent-alpine
```

**Результат**

![Screenshot_52](https://user-images.githubusercontent.com/40645030/115621281-f7ef9a80-a2fe-11eb-88c0-4ed299f1393a.png)

![Screenshot_53](https://user-images.githubusercontent.com/40645030/115621299-fb832180-a2fe-11eb-84c4-c818ee439250.png)

## 3. Docker-compose файл, который будет поднимать оба контейнера (мастер и агент) вместе с нужными нам параметрами

Чтобы docker клиент имел доступ к docker демону, можно передать через вольюм docker.sock из хостовой ОС или повозиться с docker образом, установить и настроить службу инициализации (например, system.d или init.d) при запуске контейнера. Я выбрала первый вариант :)

В файле [docker-compose](https://github.com/dahachm/CICD_exam/blob/main/jenkins_up.yml) устанавливаем вольюмы с указанием пути к каталогам для домашних директорий (чтобы иметь доступ к файлам jenkins контейнеров из хостовой ОС и хранить данные между их стартами) и пути в */var/run/docker.sock* - сокету docker по умолчанию.

Для контейнера с мастером открываем порты **8080** и **50000**, чтобы иметь доступ к webui из браузера хостовой ОС.

Для контейнера с агентом прописываем установку переменной окружения для хранения публичного SSH ключа - SSH_PUBLIC_KEY.

```
version: '3'
services:
  jenkins_master:
    image: jenkins/jenkins
    volumes:
      - ./jenkins_home_master:/var/jenkins_home:rw
      - /var/run/docker.sock:/var/run/docker.sock
    ports:
      - 9000:8080
      - 50000:50000

  jenkins_agent:
    image: dahachm/js_example:jenkins-agent-alpine
    volumes:
      - ./jenkins_home_agent:/var/jenkins_home:rw
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}
    tty: true
```

Перед запуском docker-compose нужно также:
  - создать ключи
    
    ```
    $ ssh-keygen -P '' -m PEM -f id_rsa
    ```
    
    ***
    *Столкнулась с проблемой, что ключи, сгенерированные на хостовой или любой другой ОС кроме той, что на jenkins мастере, получают ошибку авторизации при попытке связать мастера и агента. Рабочий костыль: сначала запустить контейнер с jenkins мастером, сгенерировать на нём ключи, скопировать к себе в рабочую директорию на хостовой ОС (откуда будут запускаться контейнеры через docker copmose) и снова запустить docker-compose.*   
    ***
    
  - сохранить содержимое публичного ключа в переменную SSH_PUBLIC_KEY
    
    ```
    $ export SSH_PUBLIC_KEY=$(cat id_rsa.pub)
    ```
    
  - создать домашние директории для jenkins мастера и jenkins агента  
    
    ```
    $ mkdir jenkins_home_master
    $ mkdir jenkins_home_agent
    ```

Запуск docker-compose:

```
$ docker-compose -f jenkins_up.yml up -d 
```

Результат:

![Screenshot_54](https://user-images.githubusercontent.com/40645030/115621326-01790280-a2ff-11eb-9dbb-8b7963c3132a.png)


## 4. Первоначальная настройка мастера

В моём docker-compose файле трафик с порта *8080* контейнера пробрасывается на *9000* на хостовой ОС (centos7, которая живет у меня в VM, в VBox установленном на Windows).

Так что **WebUI jenkins мастера** у меня доступен по **192.168.56.117:8080**:

![Screenshot_5](https://user-images.githubusercontent.com/40645030/115621367-135aa580-a2ff-11eb-914a-22f3fa973ff7.png)

Так как домашний каталог мы закрепили в локальном каталоге ./jenkins_home_master, то прочитать пароль можно следующим вызовом (из рабочего каталога):

```
$ cat jenkins_home_master/secrets/initialAdminPassword
```

либо отправить запрос в сам контейнер:

```
$ docker exec alpine_jenkins_master_1 cat /var/jenkins_home/sercrets/initialAdminPassword
```

Далее предлагается установить плагины (рекомендуемые или выбрать вручную):

![Screenshot_7](https://user-images.githubusercontent.com/40645030/115621343-0a69d400-a2ff-11eb-9e0a-92b1c6a48024.png)

Можно создать первого пользователя или продолжить как админ. Я создам своего пользователя admin:

![Screenshot_8](https://user-images.githubusercontent.com/40645030/115622049-05f1eb00-a300-11eb-972e-30a7e041364e.png)

Подтверждение настроек и старт:

![Screenshot_9](https://user-images.githubusercontent.com/40645030/115622055-08544500-a300-11eb-9f8c-7397550cd671.png)

![Screenshot_10](https://user-images.githubusercontent.com/40645030/115622064-0ee2bc80-a300-11eb-8fc0-c4d59c914fec.png)


**Создадим нового пользователя developer**:

![Screenshot_11](https://user-images.githubusercontent.com/40645030/115622069-11ddad00-a300-11eb-8586-2d1769fd47fb.png)

![Screenshot_12](https://user-images.githubusercontent.com/40645030/115622083-15713400-a300-11eb-93ec-81f15483ab64.png)

![Screenshot_13](https://user-images.githubusercontent.com/40645030/115622094-1904bb00-a300-11eb-98e9-c15d8576fdfb.png)

**Заданим матрицу доступа для имеющихся пользователей**:
 
  -	admin – полные права на все
  
  -	developer: 
    
      Overall: read
    
      Job: build, cancel, discover, read, workspace
    
      Agent: build 

![Screenshot_14](https://user-images.githubusercontent.com/40645030/115622112-1f933280-a300-11eb-9ded-ab55f27cd4da.png)

![Screenshot_15](https://user-images.githubusercontent.com/40645030/115622125-2326b980-a300-11eb-9047-ab28121e85b4.png)

Нужно добавить криндешиалс для взаимодействия с другими сервисами (github, dockerhub) и установки связи с агентами.

**Установка SSH закрытого ключа** (предварительного скопировать его в буфер обмена, ключ должен быть из той же пары, из которой экземпляр публичного ключа был помещен в контейнер с агентом!):

![Screenshot_16](https://user-images.githubusercontent.com/40645030/115622153-29b53100-a300-11eb-8368-0be5b61f02d0.png)

![Screenshot_17](https://user-images.githubusercontent.com/40645030/115622166-2cb02180-a300-11eb-8e31-6839ae052e7a.png)

![Screenshot_18](https://user-images.githubusercontent.com/40645030/115622181-2fab1200-a300-11eb-9987-b2ee1ee9b95d.png)

![Screenshot_19](https://user-images.githubusercontent.com/40645030/115622190-3174d580-a300-11eb-880a-fa7eb371a46a.png)

![Screenshot_20](https://user-images.githubusercontent.com/40645030/115622197-33d72f80-a300-11eb-860e-fef476087e89.png)

![Screenshot_21](https://user-images.githubusercontent.com/40645030/115622209-376ab680-a300-11eb-8758-94b0bd2c56ba.png)

Установка реквизитов для подключения к github, dockerhub происходит в том же разделе, режим `Username with password`. Нужно добавить логин и пароль.

В результате имеем следующий набор:

![Screenshot_35](https://user-images.githubusercontent.com/40645030/115622226-3cc80100-a300-11eb-95e0-a338d771481a.png)

**Установка плагинов ansible, docker:**

В разделе управления плагинами перейти во вкладку Доступные и найти нужный плагин:

![Screenshot_36](https://user-images.githubusercontent.com/40645030/115622231-3f2a5b00-a300-11eb-825a-a060e0cadefa.png)

![Screenshot_37](https://user-images.githubusercontent.com/40645030/115622237-40f41e80-a300-11eb-9dab-efbe06856dc6.png)


Ansible:

![Screenshot_28](https://user-images.githubusercontent.com/40645030/115622249-45b8d280-a300-11eb-869c-7b50b0d54086.png)

Далее в разделе Global tool configuration добавить путь к бинарнику ansible, установленному на jenkins агенте:

![Screenshot_29](https://user-images.githubusercontent.com/40645030/115622258-494c5980-a300-11eb-818d-78df8642ef09.png)

![Screenshot_30](https://user-images.githubusercontent.com/40645030/115622268-4baeb380-a300-11eb-87c7-c59f240a1a06.png)

![Screenshot_31](https://user-images.githubusercontent.com/40645030/115622277-4e110d80-a300-11eb-9640-ec3777da3913.png)


Также нужно установить плагины для docker: 

![Screenshot_34](https://user-images.githubusercontent.com/40645030/115622291-523d2b00-a300-11eb-821b-f8a6ef0ff066.png)

## 6. CI pipeline

Создание: 

Dashboard -> New Item -> [Ввести имя pipeline] и выбрать Pipeline

![Screenshot_38](https://user-images.githubusercontent.com/40645030/115622494-9d573e00-a300-11eb-8f3d-757cf6c1f171.png)

В разделе `General` выбираем `Github project` и добавляем url к репозиторию с приложением `js_example`:

![Screenshot_24](https://user-images.githubusercontent.com/40645030/115622505-a0522e80-a300-11eb-963e-90647c57c018.png)

В разделе `Build triggers` выбираем `Poll SCM ` (SCM - Source Control Management) и в `Shedule` указать `* * * * *`, что значит, что jenkins будет проверять наличие обновление в репозитории и, если недавно был коммит, то запустит новый билд.

![Screenshot_25](https://user-images.githubusercontent.com/40645030/115622510-a2b48880-a300-11eb-804c-7e6d79019372.png)

В разделе `Pipeline` в `Definition` выбрать `Pipeline script from SCM`, что указывает jenkins, что pipeline скрипт будет брать из удаленного репозитория.

Далее указываем параметры доступа к git репозиторию, указываем имя ветки, из которой брать файлы для билда и имя jenknsfil'а в репозитории (относительно корня репы). 

![Screenshot_26](https://user-images.githubusercontent.com/40645030/115622521-a516e280-a300-11eb-9b63-710bdcc9b8f6.png)

[Jenkinsfile (Declarative):](https://github.com/dahachm/student-exam2/blob/master/Jenkinsfile)

```
pipeline {
    environment {
        imagename = "dahachm/js_example"
        registryCredential = 'dockerhub_pass'
    }
    
    agent { label 'agent-1' }
    stages {
        stage('Checkout code') {
            steps {
                checkout scm
            }
        }
        
        stage('Run Python tests') {
            steps {
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install -e '.[test]'
                    coverage run -m pytest
                    coverage report
                '''
            }
        }
        
        stage('Building image') {
            steps {
                script {
                    dockerImage = docker.build imagename
                }
            }
        }

        stage('Deploy Image') {
            steps {
                script {
                    docker.withRegistry( '', registryCredential ) {
                        dockerImage.push("$BUILD_NUMBER")
                    }
                }
            }
        }

        stage('Remove Unused docker image') {
            steps {
                sh "docker rmi $imagename:$BUILD_NUMBER"
            }
        }
    }
}
```

В секии *environment* указываем переменные со значением тега образа, с под которым будем загружать его на удаленный репозиторий в docker hub и с именем реквизитов для входа в dockerhub.

### Запуск: 

Dashboard -> js_example_CI -> Build Now

или автоматически после коммита в репозитории.

### Результат

Stage Veiw - все этапы pipeline c указанием результата каждого стейджа (успех/провал, время работы):

![Screenshot_39](https://user-images.githubusercontent.com/40645030/115622536-a9db9680-a300-11eb-8815-b9e38603b51a.png)

Логи pipeline'a: 

![Screenshot_40](https://user-images.githubusercontent.com/40645030/115622543-acd68700-a300-11eb-9500-a362eb086c0e.png)

![Screenshot_41](https://user-images.githubusercontent.com/40645030/115622550-af38e100-a300-11eb-9cc0-408b241dd0be.png)


Образ добавлен в репозиторий docker hub:

![Screenshot_42](https://user-images.githubusercontent.com/40645030/115622559-b19b3b00-a300-11eb-91b7-6bb35a2977c9.png)


## 7. Ansible-playbook 

Этот playbook будет применяться в localhost, то есть внутри контейнера jenkins агента. Образ jenkins агента основа на alpine, следовательно
целевая ОС - alpine (ОС нашего агента).

Репозиторий с playbook'ом: [https://github.com/dahachm/student-exam2-ansible](https://github.com/dahachm/student-exam2-ansible)

Роли:
  - **docker**
    
    Устанавливает docker, python3 и Docker SDK for python (нужен для создания docker network через ansible playbook), запускает docker демон и создает docker network с именем {{ network_name }}, к которой будут подключены контейнеры с `js_example`, nginx и агентом (агент в ней добавляетя для того, чтобы позже смогли проверить доступность сервера nginx).
    
  - **nginx**
    
    Эта роль зависима от роли docker.
    
    Устанавливает nginx и помещает [nginx.conf](https://github.com/dahachm/student-exam2-ansible/blob/alpine/roles/nginx/templates/nginx.conf) из Jinja2 шаблона, в котором в секции *upstream* указываются переменные с именем хост и порта, на которых будут запущены приложения.
    
    Режим балансировщика - `least_conn`, что значит, что nginx будет перенаправлять запросы на тот хост, к которому сейчас меньше всего подключений. 
    
    Сам nginx поднимается на 80-м порту.

  - **web** 
    
    Эта роль зависима от роли docker.
    
    Эта роль логинится в приватный репозиторий dockerhub (реквзиты для подключения хранятся в зашифрованных  с помощью ansible-vault переменных), загружает образ с `js_example` и запускает контейнеры c открытием 5000-го порта на заданный порт и подключает их к ранее созданной docker сети.
    
В главном файле [Playbook.yml](https://github.com/dahachm/student-exam2-ansible/blob/alpine/Playbook.yml) указываются переменные `web_servers` (структура - словарь) и `network_name`, которые задают имена хостов и портов, на которых будет запускаться приложение `js_example`, и имя создаваемой docker сети соответсвенно.

```yml

  vars:
        web_servers:
               app_1: 5081 
               app_2: 5082 
               app_3: 5083
        network_name: web
```
    
Также указываю параметр `become: yes`, так как для некоторых операций (установка пакетов, например) нужны sudo права, а через интерфейс, доступный в jenkins плагине для ansible нет возможности указать параметр повышения привилегий (`-b`).

## 8. Настройка CD pipeline

**Предварительные настройки агента:**

Перейдём в контейнер и следующие команды будем выполнять внутри: 

```
$ docker exec -it alpine_jenkins_agent_1 /bin/bash
```

Создание пользователя admin и задание пароля:

```
# adduser admin
# passwd admin
```
Создание и сохранение ssh ключе для соединения admin@localhost:

```
# ssh-keygen -P '' -f ~/.ssh/id_rsa
# ssh-copy-id -i ~/.ssh/id_rsa admin@localhost
```

![Screenshot_55](https://user-images.githubusercontent.com/40645030/115623727-3dfa2d80-a302-11eb-9b8f-44fea191af9e.png)

Также нужно установить *sudo* и добавить пользователя admin в `sudoers`:

```
# apk add sudo
# echo "admin ALL=(ALL) NOPASSWD:ALL"
```

![Screenshot_56](https://user-images.githubusercontent.com/40645030/115623740-418db480-a302-11eb-8d7c-6d0e5bf4c0bb.png)

Чтобы docker отработал без ошибок, нужно проверить права `/var/run/docker.sock` были установлены в **660**, а **gid** группы docker в контейнере совпадал c gid группы docker на хостовой ОС.

Также нужно добавить пользователей jenkins и admin в группу docker.

![Screenshot_57](https://user-images.githubusercontent.com/40645030/115623747-4488a500-a302-11eb-8c91-8f48f5c638ce.png)

![Screenshot_58](https://user-images.githubusercontent.com/40645030/115623750-46eaff00-a302-11eb-9322-cdb0db2dc62c.png)

Также добавить еще две пары реквизитов в Manage credentials: vault пароль и закрытый SSH ключ для подключения к admin@localhost от имени jenkins:

![Screenshot_43](https://user-images.githubusercontent.com/40645030/115623755-49e5ef80-a302-11eb-9ccd-70ceb8215fe1.png)

![Screenshot_44](https://user-images.githubusercontent.com/40645030/115623761-4ce0e000-a302-11eb-84f1-1524e6dd90a8.png)


**Создание CD pipeline**

Настройки при создании pipelin'a такие же, как в [**п.6**](https://github.com/dahachm/CICD_exam#6), отличие только в том, что в качестве источника файла для билдов указаны новый репозиторий (с ansible playbook) и имя ветки *alpine*, а не master.

[Jenkinsfile:](https://github.com/dahachm/student-exam2-ansible/blob/alpine/Jenkinsfile)

```
pipeline {    
    agent { label 'agent-1' }
    stages {
        stage('Checkout code') {
            steps {
                checkout scm
            }
        }

        stage('Deploy with ansible playbook') {
            steps {

                ansiblePlaybook(
                    credentialsId: 'ssh_ansible', 
                    vaultCredentialsId: 'vault_pass', 
                    inventory: 'hosts', 
                    playbook: 'Playbook.yml')
            }
        }
        
        stage('Play Integration tests') {
            steps {
                sh '''
                    nginx_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' nginx)
                    answer_code=$(curl -I $nginx_IP:80 2>/dev/null | head -n1 | awk '{print $2}')
                    if (( answer_code == 200 )); 
                        then 
                            echo "SUCCESS";
                        else
                            echo "FAILURE. Server return $answer_code";
                    fi
                '''
            }               
        }
    }       
}
```

В качестве интеграционного теста здесь с помощью `curl` проверяем возвращаемый ответ сервера nginx. Запрос отправляем на адрес, который назначен контейнеру с nginx, на 80й порт.
Если возвращается 200, то выводим сообщение `SUCCESS`, что значит, что все хорошо, сервер как минимум живой. Если возвращается другой код, то выводим сообщение `FAILURE` и номер вернувшегося кода.

***
*Для этого предварительно пришлось добавить контейнер с jenkins агентом в ту же сеть, к которой уже прикреплены контейнеры app_ и nginx. 
Все из-за того, что все docker клиенты, которых мы создали в этом проекте, и "внешние", и "внутренние", обращаются к **одному и тому же docker демону**.
Так что вот такой костыль. Но я уверена, что есть способ избежать и этого, возможно, исправлю это позже.
***

**Результаты:**

Состояние pipelin'а:

![Screenshot_45](https://user-images.githubusercontent.com/40645030/115623780-51a59400-a302-11eb-8aab-21b9ca022cc1.png)

![Screenshot_46](https://user-images.githubusercontent.com/40645030/115623793-5407ee00-a302-11eb-8b40-df19dfadfd46.png)


Запущенные контейнеры:

![Screenshot_47](https://user-images.githubusercontent.com/40645030/115623807-58cca200-a302-11eb-966b-015e811804ab.png)

Сеть `web_network`, которая была создана playbook'ом:

```
$ docker network inspect web_network
```

![Screenshot_48](https://user-images.githubusercontent.com/40645030/115623810-5bc79280-a302-11eb-9a29-9b76ab852fdc.png)

Так как все контейнеры у меня на одном сервере, то в своем браузере я могу открыть их обращаясь к порту `10000` (при создании контейнера nginx поставили правило перенаправления трафика из порта 80 контейнера на порт 10000 внешней системы). 

Сейчас я создам сразу несколько сессий, открывая несколько новых вкладок в инкогнито режиме. Так как мы установили режим балансировки nginx least_conn, ожидается, что каждая вкладка будет перенаправлена на новый хост (всего три штуки).

![Screenshot_49](https://user-images.githubusercontent.com/40645030/115623817-5d915600-a302-11eb-86ae-00cd23560fa6.png)





