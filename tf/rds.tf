resource "aws_db_instance" "vault" {
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t3.micro"
  name                   = "mysqldb"
  username               = "hcadmin"
  password               = "migrateVault!"
  parameter_group_name   = "default.mysql5.7"
  vpc_security_group_ids = [aws_security_group.vault.id]
  db_subnet_group_name   = aws_db_subnet_group.mysql.id
  publicly_accessible    = true
  skip_final_snapshot    = true
}
