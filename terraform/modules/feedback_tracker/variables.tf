variable "vpc_cidr" {
  type = string
}

variable "env" {
  type = string
}

variable "DB_NAME" {
  type = string
}

variable "MYSQL_USER" {
  type = string
}

variable "db_max_acu" {
  type = number
}

variable "task_cpu" {
  type = number
}

variable "task_memory" {
  type = number
}

variable "image_tag" {
  type = string
}

variable "DB_PORT" {
  type = number
}

variable "desired_count" {
  type = number
}
