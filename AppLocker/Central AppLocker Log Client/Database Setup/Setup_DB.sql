-- ============================================
-- AppLocker Central Logging Database Setup
-- ============================================

-- Create Database
USE [master]
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'AppLockerLogs')
BEGIN
    CREATE DATABASE [AppLockerLogs]
END
GO

USE [AppLockerLogs]
GO

-- Create Table
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AppLockerLogs]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[AppLockerLogs](
        [ID] [int] IDENTITY(1,1) NOT NULL,
        [ComputerName] [nvarchar](255) NOT NULL,
        [FilePath] [nvarchar](1024) NOT NULL,
        [FilePublisher] [nvarchar](512) NULL,
        [FileHash] [nvarchar](255) NOT NULL,
        [PolicyDecision] [nvarchar](50) NOT NULL,
        [DateReported] [datetime] NOT NULL DEFAULT GETDATE(),
        CONSTRAINT [PK_AppLockerLogs] PRIMARY KEY CLUSTERED ([ID] ASC)
    )
END
GO

-- Create Index on ComputerName and FileHash for lookup performance
-- (The service checks for existing records by ComputerName + FileHash)
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = N'IX_AppLockerLogs_ComputerName_FileHash' AND object_id = OBJECT_ID(N'[dbo].[AppLockerLogs]'))
BEGIN
    CREATE NONCLUSTERED INDEX [IX_AppLockerLogs_ComputerName_FileHash] 
    ON [dbo].[AppLockerLogs] ([ComputerName], [FileHash])
END
GO

-- ============================================
-- Permissions
-- ============================================
-- Note: The Domain Computers group in the domain needs to be granted connection
-- rights to the DB instance and SELECT and INSERT permissions on the DB table.
