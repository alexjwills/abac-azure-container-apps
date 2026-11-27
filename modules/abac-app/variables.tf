variable "environment" {
  type        = string
  description = "Deployment environment"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "admin_object_id" {
  type        = string
  description = "Object ID of the admin user who uploads test data and pushes images"
}

variable "storage_replication_type" {
  type        = string
  description = "Replication for the data storage account"
  default     = "LRS"
}