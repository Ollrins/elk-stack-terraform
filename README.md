# ELK Stack as Code (Terraform + Docker + Elastic Stack 9.4)

Развёртывание полноценного ELK-стека (Elasticsearch + Logstash + Kibana + Filebeat) с тестовым приложением и дашбордом, **полностью управляемым через Terraform**.

## Архитектура

### Общая схема

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                         Yandex Cloud (ru-central1-d)                         │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                     VM: elk-lab (Ubuntu/Rocky 9)                       │  │
│  │                    4 vCPU / 8 GB RAM / 30 GB SSD                       │  │
│  │                                                                        │  │
│  │  ┌──────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Docker network: elk-network                   │  │  │
│  │  │                                                                  │  │  │
│  │  │  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐   │  │  │
│  │  │  │   myapp     │    │  Filebeat   │    │      Logstash       │   │  │  │
│  │  │  │  (Flask)    │───▶│   8.19.0    │───▶│       9.4.0        │   │  │  │
│  │  │  │  :8000      │    │  :5044 out  │    │  :5044 in (beats)   │   │  │  │
│  │  │  │  JSON logs  │    │  :5066 mon  │    │  :5000 in (tcp json)│   │  │  │
│  │  │  └─────────────┘    └─────────────┘    │  :9600 mon          │   │  │  │
│  │  │         │                  ▲           └──────────┬──────────┘   │  │  │
│  │  │         │                  │                      │              │  │  │
│  │  │         │ stdout           │ читает               │ пишет        │  │  │
│  │  │         ▼                  │ /var/lib/docker/     ▼              │  │  │
│  │  │  ┌─────────────────────────────────────┐  ┌─────────────────┐    │  │  │
│  │  │  │  /var/lib/docker/containers/*/*.log │  │  Elasticsearch  │    │  │  │
│  │  │  │  (Docker json-file driver)          │  │     9.4.0       │    │  │  │
│  │  │  └─────────────────────────────────────┘  │  :9200 HTTP     │    │  │  │
│  │  │                                            │  :9300 transport│   │  │  │
│  │  │                                            │  volume: es-data│   │  │  │
│  │  │                                            └────────┬────────┘   │  │  │
│  │  │                                                     │            │  │  │
│  │  │                                            ┌────────▼────────┐   │  │  │
│  │  │                                            │     Kibana      │   │  │  │
│  │  │                                            │      9.4.0      │   │  │  │
│  │  │                                            │  :5601 HTTP     │   │  │  │
│  │  │                                            └─────────────────┘   │  │  │
│  │  └──────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                        │  │
│  │  Порты наружу (Security Group):                                        │  │
│  │  22 (SSH), 9200 (ES), 5601 (Kibana), 5000 (Logstash TCP),              │  │
│  │  5044 (Logstash Beats), 9600 (Logstash API), 8000 (myapp)              │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  Terraform управляет: VM, VPC, subnet, Security Group, дашбордом Kibana      │
└──────────────────────────────────────────────────────────────────────────────┘
```
### Поток данных

```text
1. myapp (Flask) пишет JSON-логи в stdout
   ↓
2. Docker daemon сохраняет stdout в /var/lib/docker/containers/<id>/<id>-json.log
   ↓
3. Filebeat (type: container, format: docker) читает эти файлы
   ↓
4. Filebeat отправляет события в Logstash по протоколу Beats (порт 5044)
   ↓
5. Logstash:
   - отбрасывает логи контейнеров ELK-стека (drop {})
   - парсит message как JSON (json { source => "message" target => "parsed" })
   - раскладывает поля: level, service, logger, exception, app_timestamp, app_host
   - удаляет конфликтное поле docker
   ↓
6. Logstash пишет в Elasticsearch (индекс logs-elastic)
   ↓
7. Kibana читает logs-* и показывает в Discover / Dashboard
```

### Компоненты и их роли

| Компонент | Версия | Роль | Порты | Тома | Зависимости |
|-----------|--------|------|-------|------|-------------|
| **myapp** | — | Flask-приложение, генерирует JSON-логи | 8000 | — | — |
| **Filebeat** | 8.19.0 | Сбор логов Docker, отправка в Logstash | 5044 (out) | `/var/lib/docker/containers` (ro), `/var/run/docker.sock` (ro), `./filebeat/filebeat.yml` (ro) | logstash |
| **Logstash** | 9.4.0 | Парсинг JSON, фильтрация, отправка в ES | 5044 (beats in), 5000 (tcp json in), 9600 (mon) | `./logstash/pipeline` (ro) | elasticsearch (healthy) |
| **Elasticsearch** | 9.4.0 | Хранилище и поиск | 9200 (HTTP), 9300 (transport) | `es-data` (volume) | — |
| **Kibana** | 9.4.0 | Визуализация | 5601 | — | elasticsearch (healthy) |

### Сеть и Security Group

**Docker network `elk-network`** (bridge) — все контейнеры общаются по именам сервисов:
- `filebeat` → `logstash:5044`
- `logstash` → `elasticsearch:9200`
- `kibana` → `elasticsearch:9200`

**Security Group `elk-lab-sg`** (Yandex Cloud) — правила Ingress:

| Порт | Протокол | Назначение | Источник |
|------|----------|-----------|----------|
| 22 | TCP | SSH | 0.0.0.0/0 |
| 9200 | TCP | Elasticsearch HTTP | 0.0.0.0/0 |
| 5601 | TCP | Kibana | 0.0.0.0/0 |
| 5000 | TCP | Logstash TCP JSON | 0.0.0.0/0 |
| 5044 | TCP | Logstash Beats | 0.0.0.0/0 |
| 9600 | TCP | Logstash API | 0.0.0.0/0 |
| 8000 | TCP | myapp | 0.0.0.0/0 |
| 0–65535 | ANY | Внутренний трафик | 192.168.0.0/16 |

Egress: ANY на 0.0.0.0/0.

### Управление через Terraform

```text
terraform/
├── providers.tf        # yandex + elasticstack
├── variables.tf        # cloud_id, folder_id, zone, elk_version, kibana_ip
├── main.tf             # VPC, subnet, SG, VM, null_resource.wait_for_kibana
├── cloud-init.yaml     # Docker + ELK + myapp + конфиги (user-data)
├── dashboards.tf       # elasticstack_kibana_dashboard
└── terraform.tfvars    # значения переменных
```

**Порядок применения:**

1. `terraform apply -target=yandex_compute_instance.elk` — создаёт VM.
2. `cloud-init` внутри VM ставит Docker, поднимает ELK + myapp (3–5 минут).
3. `null_resource.wait_for_kibana` заходит по SSH и ждёт `curl -sf http://localhost:5601/api/status`.
4. `terraform apply` — создаёт дашборд через провайдер `elasticstack`.

#### Что чем управляется

| Ресурс Terraform | Что создаёт | Зависимости |
|------------------|-------------|-------------|
| `yandex_vpc_network.main` | VPC-сеть `elk-lab-network` | — |
| `yandex_vpc_subnet.main` | Подсеть `192.168.20.0/24` в зоне `ru-central1-d` | `yandex_vpc_network.main` |
| `yandex_vpc_security_group.main` | Security Group `elk-lab-sg` с правилами Ingress/Egress | `yandex_vpc_network.main` |
| `yandex_compute_instance.elk` | VM `elk-lab` (4 vCPU / 8 GB / 30 GB SSD, прерываемая) | subnet, SG |
| `null_resource.wait_for_kibana` | Ожидание готовности Kibana по SSH | `yandex_compute_instance.elk` |
| `elasticstack_kibana_dashboard.myapp_monitoring` | Дашборд `MyApp Monitoring` в Kibana | `null_resource.wait_for_kibana` |


#### Особенности

- **Провайдер `elasticstack` не умеет ждать** готовности Kibana. Поэтому используется `null_resource.wait_for_kibana` с SSH-подключением и циклом `curl -sf`.
- **IP Kibana** передаётся через переменную `kibana_ip`, потому что провайдер кэширует endpoint и не подхватывает IP из `yandex_compute_instance` автоматически.
- **`cloud-init.yaml`** — это `user-data` VM, который выполняется при первом старте. Он ставит Docker, поднимает контейнеры и копирует конфиги.

## Проверка

```bash
# Kibana
curl -I http://<IP>:5601

# Elasticsearch
curl http://<IP>:9200

# MyApp
curl http://<IP>:8000/

# Сгенерировать логи
for i in $(seq 1 10); do curl -s http://<IP>:8000/error > /dev/null; done
for i in $(seq 1 10); do curl -s http://<IP>:8000/crash > /dev/null; done

# Проверить в ES
curl -s "http://<IP>:9200/logs-elastic/_count?pretty"
```

## Дашборд в Kibana

1. Открыть `http://<IP>:5601`
2. **Stack Management → Data Views → Create data view**
   - Name: `logs`
   - Index pattern: `logs-*`
   - Time field: `@timestamp`
3. **Dashboard → MyApp Monitoring** — три панели:
   - Logs by level (Data Table)
   - Errors by service (Data Table)
   - Top error messages (Data Table)

## Особенности реализации

### Filebeat 8.19.0 вместо 9.4.0

Filebeat 9.1.0 (и 9.4.0) содержит баг: при единственном input'е краулер останавливается (`Stopping Crawler` → `Stopping 0 inputs`), и Filebeat не собирает логи. Откат на **8.19.0** решает проблему. Версия совместима с Elasticsearch/Logstash 9.x по протоколу Beats.

### Дашборд через Terraform, а не UI

Провайдер `elasticstack` 0.17.0 содержит баги валидации `axis`, `fitting`, `layers` для XY-чартов. Поэтому панели сделаны в виде `data_table` с `data_view_spec` и `terms` в `rows` — это проходит валидацию Kibana 9.4.0 без ошибок.

### `null_resource.wait_for_kibana`

Terraform не умеет ждать, пока `cloud-init` внутри VM доустановит Kibana. `null_resource` заходит по SSH и ждёт `curl -sf http://localhost:5601/api/status`, после чего создаёт дашборд.

---

### Проблема с IP при пересоздании VM

Провайдер `elasticstack` кэширует endpoint. При пересоздании VM нужно обновить `kibana_ip` в `terraform.tfvars` и выполнить `terraform apply`. Для автоматизации есть скрипт `deploy.sh` (см. ниже).

## deploy.sh (автоматизация пересоздания)

```bash
#!/bin/bash
set -e
cd ~/elk-stack-iac/terraform
terraform apply -target=yandex_compute_instance.elk -auto-approve
IP=$(terraform output -raw vm_public_ip)
sed -i "s/kibana_ip *= *\".*\"/kibana_ip = \"$IP\"/" terraform.tfvars
terraform apply -auto-approve
```

## Удаление

```bash
cd terraform
terraform destroy -auto-approve
```

## Стек

| Компонент | Версия | Роль | Образ / источник |
|-----------|--------|------|------------------|
| **Terraform** | 1.14+ | IaC: VM, VPC, subnet, SG, дашборд | `hashicorp/terraform` |
| **Yandex Cloud** | — | Облачная платформа (VM, сеть, SG) | `yandex-cloud/yandex` (провайдер) |
| **Elasticsearch** | 9.4.0 | Хранилище и поиск логов | `docker.elastic.co/elasticsearch/elasticsearch:9.4.0` |
| **Kibana** | 9.4.0 | Визуализация, Discover, Dashboard | `docker.elastic.co/kibana/kibana:9.4.0` |
| **Logstash** | 9.4.0 | Парсинг JSON, фильтрация, отправка в ES | `docker.elastic.co/logstash/logstash:9.4.0` |
| **Filebeat** | 8.19.0 | Сбор логов Docker, отправка в Logstash | `docker.elastic.co/beats/filebeat:8.19.0` |
| **myapp** | — | Flask-приложение с JSON-логами (INFO/WARN/ERROR/exception) | `python:3.11-slim` + Flask |
| **Docker** | 29.x | Контейнеризация | `docker-ce` (RHEL-репозиторий) |
| **Docker Compose** | 5.x | Оркестрация контейнеров | `docker-compose-plugin` |

### Версии и совместимость

| Компонент | Версия | Совместимость |
|-----------|--------|---------------|
| Elasticsearch | 9.4.0 | Требует Java 21+ (в образе уже есть) |
| Kibana | 9.4.0 | Должна совпадать с версией Elasticsearch |
| Logstash | 9.4.0 | Должна совпадать с версией Elasticsearch |
| Filebeat | 8.19.0 | Совместим с ES/Logstash 9.x по протоколу Beats |
| Terraform | 1.14+ | Провайдеры `yandex ~> 0.193.0`, `elasticstack ~> 0.17.0` |


### Инфраструктура

| Ресурс | Значение |
|--------|----------|
| VM | 4 vCPU / 8 GB RAM / 30 GB SSD (network-ssd) |
| Платформа | `standard-v3`, `core_fraction = 100` |
| Прерываемая | Да (`preemptible = true`) |
| Зона | `ru-central1-d` |
| ОС | Rocky Linux 9 (образ `fd828j3n8sa03unu5arm`) |
| Сеть | `192.168.20.0/24` |
| Security Group | Порты 22, 9200, 5601, 5000, 5044, 9600, 8000 |

### Docker-образы и их назначение

```text
docker.elastic.co/elasticsearch/elasticsearch:9.4.0   → хранилище и поиск
docker.elastic.co/kibana/kibana:9.4.0                 → визуализация
docker.elastic.co/logstash/logstash:9.4.0             → обработка логов
docker.elastic.co/beats/filebeat:8.19.0               → сбор логов Docker
python:3.11-slim + Flask                              → myapp (JSON-логи)
```
