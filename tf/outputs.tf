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

output "db_database_name" {
  value = module.database.db_database_name
}
output "db_instance_name" {
  value = module.database.db_instance_name
}
output "db_instance_region" {
  value = module.database.db_instance_region
}
output "db_ip_address" {
  value = module.database.db_ip_address
}

output "sa_scraper_email" {
  value = google_service_account.scraper.email
}
output "sa_frontend_server_email" {
  value = google_service_account.frontend_server.email
}

output "repository_id" {
  value = google_artifact_registry_repository.image_repo.repository_id
}
