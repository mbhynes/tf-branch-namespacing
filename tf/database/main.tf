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

resource "random_pet" "db_name_suffix" {
  length = 1
}

resource "google_compute_global_address" "db_private_ip_address" {
  provider = google-beta

  project       = var.project
  name          = "db-private-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = var.peering_subnet_address_start
  prefix_length = var.peering_subnet_prefix_size
  network       = var.network_name
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider = google-beta

  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [
    google_compute_global_address.db_private_ip_address.name,
  ]
}

resource "google_sql_database_instance" "db" {
  name                = "db-instance-${random_pet.db_name_suffix.id}"
  project             = var.project
  region              = var.region
  database_version    = "POSTGRES_13"
  deletion_protection = false

  settings {
    tier                = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }
  }

  depends_on = [
    google_service_networking_connection.private_vpc_connection
  ]
}

resource "google_sql_database" "db" {
  project  = var.project
  name     = "db"
  instance = google_sql_database_instance.db.name
}

resource "random_password" "db_password" {
  length  = 36
  special = false
  lower   = true
  upper   = true
  numeric = true
}

resource "random_password" "secret_key" {
  length  = 50
  numeric = true
  special = true
  lower   = true
  upper   = true
}

resource "google_secret_manager_secret" "server_env" {
  project   = var.project
  secret_id = "server_env"
  replication {
    automatic = true 
  }
}

resource "google_secret_manager_secret_version" "server_env" {
  secret = google_secret_manager_secret.server_env.id
  secret_data = <<EOF
DATABASE_SOCKET='postgres://${google_sql_user.django.name}:${random_password.db_password.result}@//cloudsql/${var.project}:us-east1:${google_sql_database_instance.db.name}/${google_sql_database.db.name}'
DATABASE_URL='postgres://${google_sql_user.django.name}:${random_password.db_password.result}@${google_sql_database_instance.db.private_ip_address}:5432/${google_sql_database.db.name}'
SECRET_KEY='${random_password.secret_key.result}'
PSQL_CLI_ARG='sslmode=disable dbname=${google_sql_database.db.name} host=127.0.0.1 port=5432 user=${google_sql_user.django.name} password=${random_password.db_password.result}'
EOF
}

resource "google_secret_manager_secret_iam_binding" "server_env" {
  project = google_secret_manager_secret.server_env.project
  secret_id = google_secret_manager_secret.server_env.secret_id
  role = "roles/secretmanager.secretAccessor"
  members = var.members
}

resource "google_sql_user" "django" {
  project  = var.project
  instance = google_sql_database_instance.db.name
  password = random_password.db_password.result
  name     = "django"
}
