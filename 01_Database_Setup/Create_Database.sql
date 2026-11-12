-- Create_Database.sql
-- Creates the warehouse database. Every other script starts with USE Insignia_DW.

IF DB_ID('Insignia_DW') IS NULL
    CREATE DATABASE Insignia_DW;
GO

USE Insignia_DW;
GO
