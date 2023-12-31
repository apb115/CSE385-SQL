/*
CSE 385 ToDoList Database Project
Andrew Boothe, Michael Glum
5/3/2022
*/
--************************************************************************* ENTRY
USE master
GO

IF DB_ID('ToDoList') IS NOT NULL
	DROP DATABASE ToDoList
GO

CREATE DATABASE ToDoList
GO 

USE ToDoList
GO

--************************************************************************* CREATE TABLES
CREATE TABLE Users(
	userID		INT NOT NULL		PRIMARY KEY		IDENTITY,
	userName	VARCHAR(50) NOT NULL	UNIQUE,
	Password	VARBINARY(128) NULL DEFAULT(NULL),
	Salt		UNIQUEIDENTIFIER NOT NULL DEFAULT(NEWID()),
	LoginToken	UNIQUEIDENTIFIER NULL DEFAULT(NULL),
	email		VARCHAR(50) NULL	UNIQUE,
	language	VARCHAR(30) NOT NULL	DEFAULT('English'),
	isDeleted	BIT NOT NULL		DEFAULT(0)
) 
GO

CREATE TABLE Categories(
	categoryID			INT					NOT NULL	PRIMARY KEY			IDENTITY,
	userID				INT					NOT NULL	FOREIGN KEY		REFERENCES Users(userID),
	categoryName		VARCHAR(50)			NOT NULL,
	categoryPriority	INT					NOT NULL CHECK (categoryPriority >= 1 AND categoryPriority < 11),
	color				VARCHAR(10)			NULL	DEFAULT('Blue'),
	isDeleted			BIT					NOT NULL		DEFAULT(0)
) 
GO

CREATE TABLE Items(
	itemID				INT		NOT NULL		PRIMARY KEY		IDENTITY,
	categoryID			INT						NOT NULL	FOREIGN KEY		REFERENCEs Categories(categoryID),
	itemName			VARCHAR(50)				NOT NULL,
	itemDescription		VARCHAR(100)			NULL,
	itemPriority		INT						NOT NULL DEFAULT(1) CHECK (itemPriority >= 1 AND itemPriority < 11), -- ???
	itemDueDate			SMALLDATETIME			NULL,
	dateAdded			SMALLDATETIME			NOT NULL,
	isCompleted			BIT						NOT NULL		DEFAULT(0),
	isDeleted			BIT						NOT NULL		DEFAULT(0),
	isLate				BIT						NOT NULL		DEFAULT(0)
)
GO

CREATE TABLE ErrorTable (
	errorTableId		INT				PRIMARY KEY		IDENTITY,
	ERROR_PROCEDURE		VARCHAR(200)	NULL,
	ERROR_LINE			INT				NULL,
	ERROR_MESSAGE		VARCHAR(500)	NULL,
	PARAMS				VARCHAR(MAX)	NULL,
	ERROR_NUMBER		INT				NULL,
	ERROR_SEVERITY		INT				NULL,
	ERROR_STATE			INT				NULL,
	USER_ID				VARCHAR(200)	NOT NULL,
	ERROR_DATETIME		DATETIME		NOT NULL		DEFAULT(GETDATE()),
	FIXED_DATETIME		DATETIME		NULL
)
GO
/*
USE ToDoList
GO
*/
/************************* Stored Procedures *************************/

CREATE PROCEDURE spRecordError
	@params		VARCHAR(MAX)
AS BEGIN SET NOCOUNT ON
	INSERT INTO ErrorTable
		SELECT		ERROR_PROCEDURE()
				   ,ERROR_LINE()
				   ,ERROR_MESSAGE()
				   ,@params
				   ,ERROR_NUMBER()	
				   ,ERROR_SEVERITY()
				   ,ERROR_STATE()
				   ,ORIGINAL_LOGIN()
				   ,GETDATE()
				   ,NULL
END
GO	

--************************************************************************* Login/Logout
CREATE PROCEDURE spLogin
	@userName VARCHAR(50),
	@Password  VARCHAR(50)
AS BEGIN SET NOCOUNT ON
	DECLARE @ret UNIQUEIDENTIFIER = CAST(0x0 AS UNIQUEIDENTIFIER);
		IF EXISTS(	SELECT NULL FROM Users 
					WHERE 
						userName = @userName AND
						password = HASHBYTES('SHA2_512', CAST(CONCAT(@Password, Salt) AS NVARCHAR(150)))
				) BEGIN
			SELECT @ret = LoginToken FROM Users WHERE userName = @userName;
			IF(@ret IS NULL) BEGIN
				SELECT @ret = NEWID();
				UPDATE Users SET LoginToken = @ret WHERE userName = @userName
		END
	END
	SELECT @ret AS LoginToken
END
--  Test Login
--spLogin 'userName', 'email'
GO

CREATE PROCEDURE spLogOut
	@LoginToken UNIQUEIDENTIFIER
AS BEGIN SET NOCOUNT ON
	UPDATE Users SET LoginToken = NULL WHERE LoginToken = @LoginToken
END
 --Test Logout
--spLogout 'Insert key here'
GO


--************************************************************************* Retrieving Items
CREATE PROCEDURE spGetItemsandCategories
	@LoginToken UNIQUEIDENTIFIER
AS BEGIN SET NOCOUNT ON
	DECLARE @userID INT = dbo.fnuserIDFromLoginToken(@LoginToken);
	SELECT c.categoryName, i.* 
	FROM Categories c, Items i
	WHERE @userID = c.userID AND i.categoryID = c.categoryID
END
/* -- Test Proc
	spGetItemsandCategories 'Insert LoginToken here'
*/
GO

CREATE PROCEDURE spGetUserCategories
	@LoginToken UNIQUEIDENTIFIER
AS BEGIN SET NOCOUNT ON
	DECLARE @userID INT = dbo.fnuserIDFromLoginToken(@LoginToken);
	SELECT *
	FROM Categories c, Items i
	WHERE @userID = c.userID
END
/* -- Test Proc
	spGetUserCategories 'Insert LoginToken here'
*/
GO

CREATE PROCEDURE spGetUserInfo
	@LoginToken UNIQUEIDENTIFIER
AS BEGIN SET NOCOUNT ON
	DECLARE @userID INT = dbo.fnuserIDFromLoginToken(@LoginToken);
	SELECT 
		u.userName,
		u.email,
		u.language
	FROM Users u
	WHERE @userID = u.userID
END
/* -- Test Proc
	spGetuserInfo 'Insert LoginToken Here'
*/
GO

--************************************************************************* Adds
CREATE PROCEDURE spUsers_Add
	@userName	VARCHAR(50), 
	@Password	VARCHAR(128) = NULL,
	@email		VARCHAR(50),
	@language	VARCHAR(30), 
	@isDeleted	BIT	
AS BEGIN SET NOCOUNT ON
	BEGIN TRAN
		BEGIN TRY
			IF(@userName IN (SELECT userName FROM Users)) THROW 90001, 'Username is already taken!', 1
			INSERT Users (userName, Password, email, language, isDeleted) VALUES 
				(	@userName, 
					CONVERT(varbinary(128), @Password),
					@email,
					@language, 
					@isDeleted	)
		END TRY BEGIN CATCH
			IF(@@TRANCOUNT > 0) ROLLBACK TRAN
			DECLARE @p VARCHAR(MAX) = (
				SELECT	 [userName]		=	@userName
						,[Password]		=	@Password	
						,[email]		=	@email
						,[language]		=	@language 
						,[isDeleted]	=   @isDeleted	
					FOR JSON PATH
			)
			EXEC spRecordError @p
		END CATCH
	IF(@@TRANCOUNT > 0) COMMIT TRAN
END
GO

CREATE PROCEDURE spCategories_Add
	 @userID			INT
	,@categoryName		VARCHAR(50)
	,@categoryPriority	INT
	,@color				VARCHAR(10)
	,@isDeleted			BIT
AS BEGIN SET NOCOUNT ON
	BEGIN TRAN
		BEGIN TRY
			IF(@categoryPriority < 0)
				THROW 90001, 'categoryPriority must be >= 0', 1
			INSERT INTO Categories
				SELECT	 @userID
						,@categoryName		
						,@categoryPriority	
						,@color				
						,@isDeleted
		END TRY BEGIN CATCH
			IF(@@TRANCOUNT > 0) ROLLBACK TRAN
			DECLARE @p VARCHAR(MAX) = (
				SELECT	 [@userID]				=	@userID
						,[@categoryName]		=	@categoryName		
						,[@categoryPriority]	=	@categoryPriority	
						,[@color]				=	@color				
						,[@isDeleted]			=	@isDeleted	
					FOR JSON PATH
			)
			EXEC spRecordError @p
		END CATCH
	IF(@@TRANCOUNT > 0) COMMIT TRAN
END
GO

CREATE PROCEDURE spItems_Add
	 @categoryID		INT
	,@itemName			VARCHAR(50)
	,@itemDescription	VARCHAR(100)
	,@itemPriority		INT
	,@itemDueDate		SMALLDATETIME
	,@dateAdded			SMALLDATETIME
	,@isCompleted		BIT
	,@isDeleted			BIT
	,@isLate			BIT
AS BEGIN SET NOCOUNT ON
	BEGIN TRAN
		BEGIN TRY
			IF(@itemPriority < 0)
				THROW 100001, 'itemPriority must be >= 0', 1
			IF(((@itemDueDate > @dateAdded) AND (@isLate = 1)) OR
				((@itemDueDate < @dateAdded) AND (@isLate = 0)))
				THROW 100002, 'isLate value is incorrect', 1
			INSERT INTO Items
				SELECT	 @categoryID
						,@itemName		
						,@itemDescription	
						,@itemPriority
						,@itemDueDate
						,@dateAdded
						,@isCompleted
						,@isDeleted
						,@isLate
		END TRY BEGIN CATCH
			IF(@@TRANCOUNT > 0) ROLLBACK TRAN
			DECLARE @p VARCHAR(MAX) = (
				SELECT	 
					 [@categoryID	  ] = @categoryID
					,[@itemName		  ]	= @itemName		
					,[@itemDescription]	= @itemDescription
					,[@itemPriority	  ]	= @itemPriority
					,[@itemDueDate	  ]	= @itemDueDate
					,[@dateAdded	  ]	= @dateAdded
					,[@isCompleted	  ]	= @isCompleted
					,[@isDeleted	  ]	= @isDeleted
					,[@isLate		  ]	= @isLate	
					FOR JSON PATH
			)
			EXEC spRecordError @p
		END CATCH
	IF(@@TRANCOUNT > 0) COMMIT TRAN
END
GO

--************************************************************************* Updates
CREATE PROCEDURE spUsers_Update
	 @userID	INT,
	 @userName	VARCHAR(50) = NULL, 
	 @Password	VARCHAR(128) = NULL,
	 @email		VARCHAR(50) = NULL,
	 @language	VARCHAR(30) = NULL
AS BEGIN SET NOCOUNT ON
	BEGIN TRAN
		BEGIN TRY
			IF NOT EXISTS(SELECT NULL FROM Users WHERE userID = @userID)
				THROW 90002, 'userID does not exist', 1
			IF EXISTS(SELECT NULL FROM Users WHERE (userID = @userID) AND (isDeleted = 1))
				THROW 90003, 'cannot update user because it is marked as deleted', 1
			IF @userName IN (SELECT userName FROM Users) THROW 90004, 'Username already in database', 1
			IF @email IN (SELECT email FROM Users) THROW 90005, 'Email already in database', 1
			SELECT	
				 @userID			= @userID
				,@userName			= ISNULL(@userName			, userName			)
				,@Password			= ISNULL(@Password			, Password			)
				,@email				= ISNULL(@email				, email				)
				,@language			= ISNULL(@language			, language			)
			FROM Users
			WHERE userID = @userID

			UPDATE Users SET
				 userName			=	@userName
				,Password			=	CONVERT(varbinary(128), @Password)
				,email				=	@email
				,language			=	@language
			WHERE userID = @userID
		END TRY BEGIN CATCH
			IF(@@TRANCOUNT > 0) ROLLBACK TRAN
			DECLARE @p VARCHAR(MAX) = (
				SELECT	
					 [@userID	 ] = @userID	 
					,[@userName	 ] = @userName	 
					,[@Password	 ] = @Password	 
					,[@email	 ] = @email	 
					,[@language	 ] = @language	 
					FOR JSON PATH 
			)
			EXEC spRecordError @p
		END CATCH
	IF (@@TRANCOUNT > 0) COMMIT TRAN
END
GO

CREATE PROCEDURE spCategories_Update
	 @categoryID		INT
	,@userID			INT				= NULL
	,@categoryName		VARCHAR(50)		= NULL
	,@categoryPriority	INT				= NULL
	,@color				VARCHAR(10)		= NULL
AS BEGIN SET NOCOUNT ON
	BEGIN TRAN
		BEGIN TRY
			IF NOT EXISTS(SELECT NULL FROM Categories WHERE categoryID = @categoryID)
				THROW 90002, 'categoryID does not exist', 1
			IF EXISTS(SELECT NULL FROM Categories WHERE (categoryID = @categoryID) AND (isDeleted = 1))
				THROW 90003, 'cannot update category because it is marked as deleted', 1
			SELECT	
				 @userID			= ISNULL(@userID			, userID			)	
				,@categoryName		= ISNULL(@categoryName		, categoryName		)
				,@categoryPriority	= ISNULL(@categoryPriority	, categoryPriority	)
				,@color				= ISNULL(@color				, color				)
			FROM Categories
			WHERE categoryID = @categoryID

			IF (@categoryPriority < 0)
				THROW 90001, 'categoryPriority must be >= 0', 1
			UPDATE Categories SET
				 userID				=	@userID
				,categoryName		=	@categoryName
				,categoryPriority	=	@categoryPriority
				,color				=	@color
			WHERE categoryID = @categoryID
		END TRY BEGIN CATCH
			IF(@@TRANCOUNT > 0) ROLLBACK TRAN
			DECLARE @p VARCHAR(MAX) = (
				SELECT	 [@userID]				=	@userID
						,[@categoryName]		=	@categoryName		
						,[@categoryPriority]	=	@categoryPriority	
						,[@color]				=	@color	
					FOR JSON PATH				
			)
			EXEC spRecordError @p
		END CATCH
	IF (@@TRANCOUNT > 0) COMMIT TRAN
END
GO

CREATE PROCEDURE spItems_Update
	 @itemID			INT
	,@categoryID		INT				= NULL
	,@itemName			VARCHAR(50)		= NULL
	,@itemDescription	VARCHAR(100)	= NULL
	,@itemPriority		INT				= NULL
	,@itemDueDate		SMALLDATETIME	= NULL
	,@dateAdded			SMALLDATETIME	= NULL
	,@isCompleted		BIT				= NULL
	,@isLate			BIT				= NULL
AS BEGIN SET NOCOUNT ON
	BEGIN TRAN
		BEGIN TRY
			IF NOT EXISTS(SELECT NULL FROM Items WHERE itemID = @itemID)
				THROW 100003, 'itemID does not exist', 1
			IF EXISTS(SELECT NULL FROM Items WHERE (itemID = @itemID) AND (isDeleted = 1))
				THROW 100004, 'cannot update item because it is marked as deleted', 1
			SELECT
				 @categoryID		= ISNULL(@categoryID		, categoryID		)
				,@itemName			= ISNULL(@itemName			, itemName			)
				,@itemDescription	= ISNULL(@itemDescription	, itemDescription	)
				,@itemPriority		= ISNULL(@itemPriority		, itemPriority		)
				,@itemDueDate		= ISNULL(@itemDueDate		, itemDueDate		)
				,@dateAdded			= ISNULL(@dateAdded			, dateAdded			)
				,@isCompleted		= ISNULL(@isCompleted		, isCompleted		)
				,@isLate			= ISNULL(@isLate			, isLate			)
			FROM Items
			WHERE itemID = @itemID

			IF (@itemPriority < 0)
				THROW 90001, 'itemPriority must be >= 0', 1
			UPDATE Items SET
				 categoryID			=	@categoryID		
				,itemName			=	@itemName			
				,itemDescription	=	@itemDescription	
				,itemPriority		=	@itemPriority		
				,itemDueDate		=	@itemDueDate		
				,dateAdded			=	@dateAdded			
				,isCompleted		=	@isCompleted				
				,isLate				=	@isLate			
			WHERE itemID = @itemID
		END TRY BEGIN CATCH
			IF(@@TRANCOUNT > 0) ROLLBACK TRAN
			DECLARE @p VARCHAR(MAX) = (
				SELECT	 
					 [categoryID	 ]	=	@categoryID		
					,[itemName		 ]	=	@itemName		
					,[itemDescription]	=	@itemDescription
					,[itemPriority	 ]	=	@itemPriority	
					,[itemDueDate	 ]	=	@itemDueDate	
					,[dateAdded		 ]	=	@dateAdded		
					,[isCompleted	 ]	=	@isCompleted		
					,[isLate		 ]	=	@isLate	
					FOR JSON PATH	
			)
			EXEC spRecordError @p
		END CATCH
	IF (@@TRANCOUNT > 0) COMMIT TRAN
END
GO

--************************************************************************* Deletes
CREATE PROCEDURE spUsers_Delete
	@userID INT
AS BEGIN SET NOCOUNT ON
	BEGIN TRAN
		BEGIN TRY
			IF NOT EXISTS(SELECT NULL FROM Users WHERE userID = @userID)
				THROW 90000, 'User does not exist', 1
			IF EXISTS(SELECT NULL FROM Users WHERE (userID = @userID) AND (isDeleted = 1))
				THROW 90004, 'User was already deleted', 1
			UPDATE Users SET isDeleted = 1 WHERE userID = @userID
		END TRY BEGIN CATCH
			IF(@@TRANCOUNT > 0) ROLLBACK TRAN
			DECLARE @p VARCHAR(MAX) = (
				SELECT [@userID] = @userID
			)
			EXEC spRecordError @p
		END CATCH
	IF(@@TRANCOUNT > 0) COMMIT TRAN
END
GO

CREATE PROCEDURE spCategories_Delete
	@categoryID INT
AS BEGIN SET NOCOUNT ON
	BEGIN TRAN
		BEGIN TRY
			IF NOT EXISTS(SELECT NULL FROM Categories WHERE categoryID = @categoryID)
				THROW 90000, 'categoryID does not exist', 1
			IF EXISTS(SELECT NULL FROM Categories WHERE (categoryID = @categoryID) AND (isDeleted = 1))
				THROW 90004, 'Category was already deleted', 1
			UPDATE Categories SET isDeleted = 1 WHERE categoryID = @categoryID
		END TRY BEGIN CATCH
			IF(@@TRANCOUNT > 0) ROLLBACK TRAN
			DECLARE @p VARCHAR(MAX) = (
				SELECT [@categoryID] = @categoryID
			)
			EXEC spRecordError @p
		END CATCH
	IF(@@TRANCOUNT > 0) COMMIT TRAN
END
GO

CREATE PROCEDURE spItems_Delete
	@itemID INT
AS BEGIN SET NOCOUNT ON
	BEGIN TRAN
		BEGIN TRY
			IF NOT EXISTS(SELECT NULL FROM Items WHERE itemID = @itemID)
				THROW 90000, 'itemID does not exist', 1
			IF EXISTS(SELECT NULL FROM Items WHERE (itemID = @itemID) AND (isDeleted = 1))
				THROW 90004, 'item was already deleted', 1
			UPDATE Items SET isDeleted = 1 WHERE itemID = @itemID
		END TRY BEGIN CATCH
			IF(@@TRANCOUNT > 0) ROLLBACK TRAN
			DECLARE @p VARCHAR(MAX) = (
				SELECT [@itemID] = @itemID
			)
			EXEC spRecordError @p
		END CATCH
	IF(@@TRANCOUNT > 0) COMMIT TRAN
END
GO

--/****************************** Functions ****************************/

--******************************************************************************DONE
CREATE FUNCTION fnuserIDFromLoginToken (@loginToken uniqueidentifier) RETURNS INT AS BEGIN
	IF(@loginToken IS NULL) RETURN 0;
	DECLARE @ret INT = (SELECT userID FROM Users WHERE LoginToken = @loginToken)
	return ISNULL(@ret,0)
END
/* -- Test function
	SELECT dbo.fnuserIDFromLoginToken(NEWID())
*/
GO

/**************************** Data Input *****************************/

INSERT INTO Users (userName, email, language) VALUES
('andrewboothe1', 'ghardcastle0@google.cn', 'Montenegrin1'),
('andrewboothe2', 'ghardcastle1@google.cn', 'Montenegrin2'),
('andrewboothe3', 'ghardcastle2@google.cn', 'Montenegrin3'),
('andrewboothe4', 'ghardcastle3@google.cn', 'Montenegrin4'),
('andrewboothe5', 'ghardcastle4@google.cn', 'Montenegrin5'),
('andrewboothe6', 'ghardcastle5@google.cn', 'Montenegrin6'),
('andrewboothe7', 'ghardcastle6@google.cn', 'Montenegrin7'),
('andrewboothe8', 'ghardcastle7@google.cn', 'Montenegrin8'),
('andrewboothe9', 'ghardcastle8@google.cn', 'Montenegrin9'),
('andrewboothe10', 'ghardcastl9@google.cn', 'Montenegrin10')
GO

INSERT INTO Categories (userID, categoryName, categoryPriority, color) VALUES
(7, 'Work', 2, 'Blue'),	   
(7, 'Home', 2, 'Blue'),	
(10, 'School', 2, 'Blue'), 	
(10, 'Work', 2, 'Blue'),   	
(10, 'Work', 2, 'Blue'),
(5, 'Work', 2, 'Blue'),
(5, 'School', 2, 'Blue'),
(2, 'School', 2, 'Blue'),
(2, 'Work', 4, 'Blue'),
(1, 'Home', 2, 'Blue'),
(1, 'Work', 10, 'Blue'),
(4, 'Work', 1, 'Blue'),
(4, 'Home', 2, 'Blue'),
(4, 'Work', 2, 'Blue'),
(6, 'Extra Stuff', 2, 'Blue'),
(6, 'Work', 9, 'Blue'),
(8, 'Work', 7, 'Blue'),
(9, 'Jury Duty', 2, 'Blue'),
(9, 'Work', 2, 'Blue'),
(3, 'Work', 2, 'Blue'),
(3, 'Work', 3, 'Blue'),
(2, 'Extracurriculars', 2, 'Blue'),
(1, 'Procrastination', 2, 'Blue')
GO

INSERT INTO Items(categoryID, itemName, itemDescription, itemPriority, itemDueDate, dateAdded, isCompleted, isLate) VALUES
(2, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(12, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(11, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(5, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(4, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(3, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(2, 'Calculus', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(1, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(13, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(14, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(15, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(18, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0),
(21, 'Algebra', 'Due Friday', 7, '01-01-2017', '12-10-2016', 0, 0)
GO


UPDATE Users SET Password = HASHBYTES('SHA2_512', CAST(CONCAT(email, Salt) AS NVARCHAR(150)))
GO


CREATE NONCLUSTERED INDEX IX_Users_userID ON Users(
	userID ASC
)
GO

CREATE NONCLUSTERED INDEX IX_Categories_categoryID ON Categories(
	categoryID ASC
)
GO

CREATE NONCLUSTERED INDEX IX_Items_itemID ON Items(
	itemID ASC
)
GO

USE master
GO

ALTER DATABASE ToDoList SET  READ_WRITE 
GO

