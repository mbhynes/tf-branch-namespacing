# ==============================================================================
# MIT License
#
# Copyright (c) 2022 Michael B Hynes
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ==============================================================================

terraform {
  backend "gcs" {
    prefix = "terraform/tfstate"
  }
}

resource "google_compute_project_default_network_tier" "default" {
  project      = var.project_id
  network_tier = "STANDARD"
}

module "project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 13.0"

  project_id = var.project_id
  activate_apis = [
    "artifactregistry.googleapis.com",
    "cloudapis.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "containerregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "oslogin.googleapis.com",
    "monitoring.googleapis.com",
    "networkmanagement.googleapis.com",
    "secretmanager.googleapis.com",
    "servicemanagement.googleapis.com",
    "servicenetworking.googleapis.com",
    "serviceusage.googleapis.com",
    "sql-component.googleapis.com",
    "sqladmin.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com",
    "storage.googleapis.com",
    "vpcaccess.googleapis.com",
  ]
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 4.0"

  project_id   = var.project_id
  network_name = "net-01"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = "bastion-01"
      subnet_ip     = "10.0.1.0/24"
      subnet_region = var.region
      description   = "subnet.bastion.${var.region}"
    },
    {
      subnet_name   = "compute-01"
      subnet_ip     = "10.0.2.0/24"
      subnet_region = var.region
      description   = "subnet.compute.${var.region}"
    },
    {
      subnet_name   = "db-01"
      subnet_ip     = "10.0.3.0/24"
      subnet_region = var.region
      description   = "subnet.db.${var.region}"
    },
    {
      subnet_name   = "conn-gae-01"
      subnet_ip     = "10.254.0.0/28"
      subnet_region = var.region
      description   = "subnet.conn-gae.${var.region}"
    },
  ]
  routes = [
    {
      name              = "egress-internet"
      description       = "Route through IGW to access internet"
      destination_range = "0.0.0.0/0"
      tags              = "egress-inet"
      next_hop_internet = "true"
    },
  ]

  depends_on = [
    module.project_services,
    google_compute_project_default_network_tier.default,
  ]
}

module "nat" {
  source  = "terraform-google-modules/cloud-nat/google"
  version = "~> 2.0.0"

  name = "nat"
  project_id = var.project_id
  network = module.vpc.network_id
  region = var.region
  create_router = true
  router = "nat-router"

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetworks = [{
    name = module.vpc.subnets["${var.region}/bastion-01"].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    secondary_ip_range_names = []
  }]
}

module "serverless-connector" {
  source     = "terraform-google-modules/network/google//modules/vpc-serverless-connector-beta"
  project_id = var.project_id
  vpc_connectors = [{
    name            = "serverless-conn"
    region          = var.region
    subnet_name     = module.vpc.subnets["${var.region}/conn-gae-01"].name
    machine_type    = "e2-micro"
    min_instances   = 2
    max_instances   = 3
  }]
}

resource "google_artifact_registry_repository" "image_repo" {
  provider      = google-beta
  project       = var.project_id
  location      = var.region
  repository_id = "imgrepo"
  format        = "DOCKER"

  depends_on = [
    module.project_services
  ]
}

resource "google_service_account" "frontend_server" {
  project      = var.project_id
  account_id   = "server"
  display_name = "Frontend Server Service Account"
}

resource "google_service_account" "scraper" {
  project      = var.project_id
  account_id   = "scraper"
  display_name = "Feedgrid webscraper"
}

resource "google_artifact_registry_repository_iam_member" "scraper" {
  provider   = google-beta
  project    = google_artifact_registry_repository.image_repo.project
  location   = google_artifact_registry_repository.image_repo.location
  repository = google_artifact_registry_repository.image_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.scraper.email}"
}

resource "google_project_iam_member" "frontend_server" {
  depends_on = [
    google_service_account.frontend_server,
  ]
  for_each = toset([
    "roles/appengine.serviceAgent",
    "roles/bigquery.dataEditor",
    "roles/cloudsql.client",
    "roles/cloudsql.instanceUser",
    "roles/secretmanager.viewer",
    "roles/storage.objectViewer",
  ])
  project  = var.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.frontend_server.email}"
}

resource "google_project_iam_member" "scraper" {
  for_each = toset([
    "roles/compute.instanceAdmin.v1",
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
    "roles/secretmanager.viewer",
  ])
  project  = var.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.scraper.email}"
}

resource "google_storage_bucket" "storage_private" {
  project       = var.project_id
  name          = "storage-private.${var.target_env}.${var.domain}"
  location      = "US"
  force_destroy = true
}

resource "google_storage_bucket_acl" "storage_private" {
  bucket = google_storage_bucket.storage_private.name
  role_entity = [
    "WRITER:user-${google_service_account.frontend_server.email}",
  ]
}

resource "google_storage_bucket" "storage_public" {
  project       = var.project_id
  name          = "storage-public.${var.target_env}.${var.domain}"
  location      = "US"
  force_destroy = true
}

resource "google_storage_bucket_acl" "storage_public" {
  bucket = google_storage_bucket.storage_public.name
  role_entity = [
    "WRITER:user-${google_service_account.frontend_server.email}",
  ]
}

resource "google_storage_bucket_iam_member" "storage_public_ro" {
  bucket = google_storage_bucket.storage_public.name
  role = "roles/storage.legacyObjectReader"
  member = "allUsers"
  depends_on = [
    google_storage_bucket_acl.storage_public,
  ]
}

module "database" {
  source  = "./database"
  project = var.project_id
  region  = var.region
  network_id = module.vpc.network_id
  network_name = module.vpc.network_name
  peering_subnet_address_start = "10.255.0.0"
  peering_subnet_prefix_size = 16
  members = [
    "serviceAccount:${google_service_account.frontend_server.email}",
    "serviceAccount:${google_service_account.scraper.email}",
  ]
  depends_on = [
    module.project_services,
    module.vpc,
  ]
}

module "iap_bastion" {
  source = "terraform-google-modules/bastion-host/google"

  project          = var.project_id
  network          = module.vpc.network_self_link
  subnet           = module.vpc.subnets["${var.region}/bastion-01"].self_link
  zone             = "${var.region}-b"
  machine_type     = "e2-micro"
  name             = "bastion"
  tags             = ["bastion"]
  additional_ports = ["5432"]

  service_account_roles_supplemental = [
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
    "roles/compute.instanceAdmin.v1",
    "roles/compute.networkUser",
    "roles/compute.networkViewer",
    "roles/compute.viewer",
    "roles/compute.osLogin",
    "roles/iam.serviceAccountUser",
    "roles/iap.tunnelResourceAccessor",
  ]

  startup_script = <<EOF
sudo su
cd /usr/local/bin
curl https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -o cloud_sql_proxy && date > /tmp/proxy.download.success  
chmod +x cloud_sql_proxy && date > /tmp/proxy.chmod.success
cat > /etc/systemd/system/cloud-sql-proxy.service <<eof

[Unit]
Description=Cloud SQL Proxy to Postgresql database insances
Documentation=https://cloud.google.com/sql/docs/mysql/connect-compute-engine
Requires=networking.service
After=networking.service

[Service]
WorkingDirectory=/usr/local/bin
ExecStart=/usr/local/bin/cloud_sql_proxy -dir=/var/run/cloud-sql-proxy -instances="${var.project_id}:${module.database.db_instance_region}:${module.database.db_instance_name}=tcp:5432"
Restart=always
StandardOutput=journal
User=root

[Install]
WantedBy=multi-user.target
eof

systemctl daemon-reload && date > /tmp/proxy.systectlreload.success 
systemctl start cloud-sql-proxy && date > /tmp/proxy.systemctlstart.success
EOF

  depends_on = [
    module.project_services,
    module.database,
    module.vpc,
  ]
}

module "network_firewall_rules" {
  source       = "terraform-google-modules/network/google//modules/firewall-rules"
  project_id   = var.project_id
  network_name = module.vpc.network_name

  rules = [{
    name                    = "deny-all-ingress"
    priority                = 5000
    direction               = "INGRESS"
    ranges                  = ["0.0.0.0/0"]
    description             = null
    log_config              = null
    source_service_accounts = null
    target_service_accounts = null
    source_tags             = null
    target_tags             = null
    allow                   = []
    deny = [{
      protocol = "tcp"
      ports = ["0-65535"]
    }, {
      protocol = "udp"
      ports = ["0-65535"]
    }, {
      protocol = "icmp"
      ports = []
    }]
    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }, {
    name                    = "allow-internal-ingress"
    priority                = 3000
    direction               = "INGRESS"
    ranges                  = ["10.0.0.0/8"]
    description             = null
    log_config              = null
    source_service_accounts = null
    target_service_accounts = null
    source_tags             = null
    target_tags             = null
    deny                    = []
    allow = [{
      protocol = "tcp"
      ports = ["0-65535"]
    }, {
      protocol = "udp"
      ports = ["0-65535"]
    }, {
      protocol = "icmp"
      ports = []
    }]
    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }, {
    name                    = "allow-compute-egress"
    priority                = 3000
    direction               = "EGRESS"
    ranges                  = [module.vpc.subnets["${var.region}/compute-01"].ip_cidr_range]
    description             = null
    log_config              = null
    source_service_accounts = null
    target_service_accounts = null
    source_tags             = null
    target_tags             = null
    deny                    = []
    allow = [{
      protocol = "tcp"
      ports = ["0-65535"]
    }, {
      protocol = "udp"
      ports = ["0-65535"]
    }, {
      protocol = "icmp"
      ports = []
    }]
    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }, {
    name                    = "allow-bastion-egress"
    priority                = 1000
    direction               = "EGRESS"
    ranges                  = ["0.0.0.0/0"]
    description             = null
    log_config              = null
    source_service_accounts = null
    target_service_accounts = null
    source_tags             = null
    target_tags             = ["bastion"]
    deny                    = []
    allow = [{
      protocol = "tcp"
      ports = ["0-65535"]
    }, {
      protocol = "udp"
      ports = ["0-65535"]
    }, {
      protocol = "icmp"
      ports = []
    }]
    log_config = {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }]
  depends_on = [
    module.project_services,
    module.iap_bastion,
  ]
}
