import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import fetch from 'node-fetch';
const server = new Server({
    name: "r-acquaint",
    version: "1.0.0"
}, {
    capabilities: {
        tools: {}
    }
});
async function executeR(rCode) {
    const sessionServerUrl = process.env.R_SESSION_SERVER_URL || 'http://127.0.0.1:8081';
    const response = await fetch(sessionServerUrl, {
        method: 'POST',
        body: rCode,
        headers: {
            'Content-Type': 'text/plain'
        }
    });
    if (!response.ok) {
        throw new Error(`Session server responded with status: ${response.status}`);
    }
    return await response.text();
}
// Register tools that map to btw functions
const toolsListSchema = z.object({
    method: z.literal("tools/list"),
    params: z.object({}).optional()
});
server.setRequestHandler(toolsListSchema, async () => {
    return {
        tools: [
            {
                name: "get_installed_packages",
                description: "Lists the names of all installed R packages along with their titles.",
                inputSchema: {
                    type: "object",
                    properties: {}
                }
            },
            {
                name: "get_package_help_topics",
                description: "Returns the topic_id, title, and aliases fields for every topic in a package's documentation as a JSON-formatted string. Use this to find available documentation in a package.",
                inputSchema: {
                    type: "object",
                    properties: {
                        package_name: {
                            type: "string",
                            description: "The exact name of the package, e.g. 'shiny'"
                        }
                    },
                    required: ["package_name"]
                }
            },
            {
                name: "get_help_page",
                description: "Returns the complete help page for a package topic as plain text, including examples, descriptions, parameters, and return values.",
                inputSchema: {
                    type: "object",
                    properties: {
                        topic: {
                            type: "string",
                            description: "The topic_id or alias of the help page, e.g. 'withProgress' or 'incProgress'"
                        },
                        package_name: {
                            type: "string",
                            description: "The exact name of the package, e.g. 'shiny'"
                        }
                    },
                    required: ["package_name", "topic"]
                }
            },
            {
                name: "get_package_vignettes",
                description: "Lists all vignettes available in a specific R package as a JSON array of vignette names and titles. Vignettes are articles describing key concepts or features of an R package.",
                inputSchema: {
                    type: "object",
                    properties: {
                        package_name: {
                            type: "string",
                            description: "The exact name of the package, e.g. 'shiny'"
                        }
                    },
                    required: ["package_name"]
                }
            },
            {
                name: "get_vignette",
                description: "Retrieves a specific vignette from an R package in plain text format. Vignettes provide in-depth tutorials and explanations about package functionality.",
                inputSchema: {
                    type: "object",
                    properties: {
                        package_name: {
                            type: "string",
                            description: "The exact name of the package, e.g. 'shiny'"
                        },
                        vignette_name: {
                            type: "string",
                            description: "The name of the vignette to retrieve. If omitted, retrieves the introductory vignette for the package."
                        }
                    },
                    required: ["package_name"]
                }
            },
            {
                name: "describe_data_frame",
                description: "Show the data frame or table or get information about the structure of a data frame or table.",
                inputSchema: {
                    type: "object",
                    properties: {
                        data_frame: {
                            type: "string",
                            description: "The name of the data frame."
                        },
                        format: {
                            type: "string",
                            description: "The output format of the data frame: 'skim', 'glimpse', 'print', or 'json'. Default 'skim'.\n\n* skim: Returns a JSON object with information about every column in the table.\n* glimpse: Returns the number of rows, columns, column names and types and the first values of each column\n* print: Prints the data frame\n* json: Returns the data frame as JSON"
                        },
                        dims: {
                            type: "array",
                            items: {
                                type: "integer"
                            },
                            description: "Dimensions of the data frame to use for the \"print\" or \"json\" format. A numeric vector of length 2 as number of rows and columns. Default `c(5, 100)`."
                        }
                    },
                    required: ["data_frame"]
                }
            },
            {
                name: "describe_environment",
                description: "List and describe items in the global environment.",
                inputSchema: {
                    type: "object",
                    properties: {
                        items: {
                            type: "array",
                            items: {
                                type: "string"
                            },
                            description: "The names of items to describe from the environment. In omitted, describes all items."
                        }
                    }
                },
                required: []
            },
            {
                name: "session_package_info",
                description: "Verify that a specific package is installed, or find out which packages are in use in the current session. As a last resort, this function can also list all installed packages.",
                inputSchema: {
                    type: "object",
                    properties: {
                        packages: {
                            type: "string",
                            description: "Provide a commma-separated list of package names to check that these packages are installed and to confirm which versions of the packages are available. Use the single string \"attached\" to show packages that have been attached by the user, i.e. are explicitly in use in the session. Use the single string \"loaded\" to show all packages, including implicitly loaded packages, that are in use in the session (useful for debugging). Finally, the string \"installed\" lists all installed packages. Try using the other available options prior to listing all installed packages.",
                            required: true
                        },
                        dependencies: {
                            type: "string",
                            description: "When describing the installed or loaded version of a specific package, you can use `dependencies = \"true\"` to list dependencies of the package. Alternatively, you can give a comma-separated list of dependency types, choosing from `\"Depends\"`, `\"Imports\"`, `\"Suggests\"`, `\"LinkingTo\"`, `\"Enhances\"`.",
                            required: false
                        }
                    },
                    required: ["packages"]
                }
            },
            {
                name: "session_platform_info",
                description: "Describes the R version, operating system, language and locale settings for the user's system.",
                inputSchema: {
                    type: "object",
                    properties: {},
                    required: []
                }
            }
        ]
    };
});
const toolsCallSchema = z.object({
    method: z.literal("tools/call"),
    params: z.object({
        name: z.string(),
        arguments: z.any()
    })
});
server.setRequestHandler(toolsCallSchema, async (request) => {
    const { name, arguments: args } = request.params;
    try {
        let result;
        switch (name) {
            case "get_installed_packages":
                result = await executeR(`
          cat(btw::btw_tool_session_package_info(packages = "installed"))
        `);
                break;
            case "get_package_help_topics":
                result = await executeR(`
          cat(btw::btw_tool_docs_package_help_topics("${args.package_name}"))
        `);
                break;
            case "get_help_page":
                result = await executeR(`
          cat(btw::btw_tool_docs_help_page("${args.topic}", "${args.package_name}"))
        `);
                break;
            case "get_package_vignettes":
                result = await executeR(`
          cat(btw::btw_tool_docs_available_vignettes("${args.package_name}"))
        `);
                break;
            case "get_vignette":
                const vignetteName = args.vignette_name || args.package_name;
                result = await executeR(`
          cat(btw::btw_tool_docs_vignette("${args.package_name}", "${vignetteName}"))
        `);
                break;
            case "describe_data_frame":
                const dataFrameName = args.data_frame;
                const dataFrameFormat = args.format || "skim";
                const dataFrameDims = args.dims ? JSON.stringify(args.dims) : "c(5, 100)";
                result = await executeR(`
          cat(btw::btw_tool_env_describe_data_frame("${dataFrameName}", "${dataFrameFormat}", ${dataFrameDims}))
        `);
                break;
            case "describe_environment":
                let itemsArg = "NULL";
                if (args.items && Array.isArray(args.items) && args.items.length > 0) {
                    itemsArg = `c(${args.items.map((item) => `"${item}"`).join(", ")})`;
                    result = await executeR(`
            cat(btw::btw_tool_env_describe_environment(items = ${itemsArg}))
          `);
                }
                else {
                    result = await executeR(`cat(btw::btw_tool_env_describe_environment())`);
                }
                break;
            case "session_package_info":
                const dependenciesArg = args.dependencies || "";
                result = await executeR(`
          cat(btw::btw_tool_session_package_info("${args.packages}", "${dependenciesArg}"))
        `);
                break;
            case "session_platform_info":
                result = await executeR(`cat(btw::btw_tool_session_platform_info())`);
                break;
            default:
                throw new Error(`Unknown tool: ${name}`);
        }
        return {
            content: [
                {
                    type: "text",
                    text: result
                }
            ]
        };
    }
    catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        return {
            isError: true,
            content: [
                {
                    type: "text",
                    text: `Error executing tool ${name}: ${errorMessage}`
                }
            ]
        };
    }
});
// Start the server
async function main() {
    try {
        const transport = new StdioServerTransport();
        await server.connect(transport);
    }
    catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        console.error("Error starting server:", errorMessage);
        process.exit(1);
    }
}
main();
