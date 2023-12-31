CREATE PROCEDURE [dbo].[sp_CustomerRevenue]
@FromYear INT = NULL,
@ToYear INT = NULL,
@Period VARCHAR(10) = 'Y',
@CustomerID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATE, @EndDate DATE;
    DECLARE @TableName NVARCHAR(128), @SqlCmd NVARCHAR(MAX);

    -- Set StartDate and EndDate based on input parameters
    SET @StartDate = ISNULL(CAST(@FromYear AS NVARCHAR(4)) + '-01-01', (SELECT MIN([Invoice Date Key]) FROM [Fact].[Sale]));
    SET @EndDate = ISNULL(CAST(@ToYear AS NVARCHAR(4)) + '-12-31', (SELECT MAX([Invoice Date Key]) FROM [Fact].[Sale]));

    -- Create dynamic table name
    SET @TableName = 
    CASE 
        WHEN @CustomerID IS NOT NULL THEN 
            CAST(@CustomerID AS NVARCHAR(10)) + '_' + 
            CAST(@FromYear AS NVARCHAR(4)) + 
            (CASE WHEN @FromYear <> @ToYear THEN '_' + CAST(@ToYear AS NVARCHAR(4)) ELSE '' END) + 
            '_' + LEFT(@Period, 1)
        ELSE
            'All_' + CAST(@FromYear AS NVARCHAR(4)) + 
            (CASE WHEN @FromYear <> @ToYear THEN '_' + CAST(@ToYear AS NVARCHAR(4)) ELSE '' END) + 
            '_' + LEFT(@Period, 1)
    END;

    -- Create a temporary table for the results
    CREATE TABLE #TempResults
    (
        [CustomerID] INT,
        [CustomerName] NVARCHAR(50),
        [Period] NVARCHAR(8),
        [Revenue] NUMERIC(19,2)
    );

    -- Insert data into the temporary table
    INSERT INTO #TempResults
    SELECT 
        s.[Customer Key] AS [CustomerID],
        c.[Customer] AS [CustomerName],
        CASE 
            WHEN @Period IN ('M', 'Month') THEN FORMAT(s.[Invoice Date Key], 'MMM yyyy')
            WHEN @Period IN ('Q', 'Quarter') THEN 'Q' + CAST(DATEPART(QUARTER, s.[Invoice Date Key]) AS NVARCHAR(1)) + ' ' + CAST(YEAR(s.[Invoice Date Key]) AS NVARCHAR(4))
            ELSE CAST(YEAR(s.[Invoice Date Key]) AS NVARCHAR(4))
        END AS Period,
        ISNULL(SUM(s.Quantity * s.[Unit Price]),0) AS Revenue
    FROM [Fact].[Sale] s
    JOIN [Dimension].[Customer] c ON s.[Customer Key] = c.[Customer Key]
    WHERE s.[Invoice Date Key] BETWEEN @StartDate AND @EndDate
    AND (@CustomerID IS NULL OR s.[Customer Key] = @CustomerID)
    GROUP BY s.[Customer Key], c.[Customer], 
    CASE 
        WHEN @Period IN ('M', 'Month') THEN FORMAT(s.[Invoice Date Key], 'MMM yyyy')
        WHEN @Period IN ('Q', 'Quarter') THEN 'Q' + CAST(DATEPART(QUARTER, s.[Invoice Date Key]) AS NVARCHAR(1)) + ' ' + CAST(YEAR(s.[Invoice Date Key]) AS NVARCHAR(4))
        ELSE CAST(YEAR(s.[Invoice Date Key]) AS NVARCHAR(4))
    END;

    -- Drop the target table if it exists and then create it
    SET @SqlCmd = 'IF OBJECT_ID(''' + @TableName + ''', ''U'') IS NOT NULL DROP TABLE ' + @TableName + ';
                   CREATE TABLE ' + @TableName + ' ([CustomerID] INT, [CustomerName] NVARCHAR(50), [Period] NVARCHAR(8), [Revenue] NUMERIC(19,2));';
    EXEC sp_executesql @SqlCmd;

    -- Copy data from the temporary table to the final table
    SET @SqlCmd = 'INSERT INTO ' + @TableName + ' SELECT * FROM #TempResults';
    EXEC sp_executesql @SqlCmd;

    -- Display results from the final table
    SET @SqlCmd = 'SELECT * FROM ' + @TableName;
    EXEC sp_executesql @SqlCmd;

    -- Clean up the temporary table
    DROP TABLE #TempResults;

    SET NOCOUNT OFF;
END
